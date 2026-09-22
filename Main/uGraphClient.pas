unit uGraphClient;

interface

type
  TGraphMailInfo = record
    ImmutableID: string;
    InternetMessageID: string;
    Subject: string;
    ParentFolderID: string;
    ReceivedDateTime: string;
  end;

  TGraphClient = class sealed
  private
    class function ODataStringLiteral(const Value: string): string; static;
  public
    class function FindMailByInternetMessageID(
      const AccessToken, InternetMessageID: string;
      out Mail: TGraphMailInfo;
      out ErrorText: string
    ): Boolean; static;
    class function TranslateExchangeID(
      const AccessToken, InputID, SourceIDType, TargetIDType: string;
      out TargetID, ErrorText: string
    ): Boolean; static;
    class function GetMailByImmutableID(
      const AccessToken, ImmutableID: string;
      out Mail: TGraphMailInfo;
      out ErrorText: string
    ): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Net.HttpClient,
  System.Net.URLClient;

function JsonString(const Obj: TJSONObject; const Name: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  if Obj = nil then
    Exit;
  Value := Obj.GetValue(Name);
  if Value <> nil then
    Result := Value.Value;
end;

function GraphErrorText(
  const Root: TJSONObject;
  const StatusCode: Integer;
  const StatusText: string
): string;
var
  ErrorObj: TJSONObject;
begin
  Result := Format('HTTP %d %s', [StatusCode, StatusText]);
  if Root = nil then
    Exit;
  ErrorObj := Root.GetValue('error') as TJSONObject;
  if ErrorObj <> nil then
  begin
    if JsonString(ErrorObj, 'code') <> '' then
      Result := Result + ': ' + JsonString(ErrorObj, 'code');
    if JsonString(ErrorObj, 'message') <> '' then
      Result := Result + ' - ' + JsonString(ErrorObj, 'message');
  end;
end;

procedure ReadMail(const Obj: TJSONObject; out Mail: TGraphMailInfo);
begin
  Mail := Default(TGraphMailInfo);
  if Obj = nil then
    Exit;
  // Wegen Prefer: IdType="ImmutableId" ist Graphs Feld "id" hier die ImmutableID.
  Mail.ImmutableID := JsonString(Obj, 'id');
  Mail.InternetMessageID := JsonString(Obj, 'internetMessageId');
  Mail.Subject := JsonString(Obj, 'subject');
  Mail.ParentFolderID := JsonString(Obj, 'parentFolderId');
  Mail.ReceivedDateTime := JsonString(Obj, 'receivedDateTime');
end;

class function TGraphClient.ODataStringLiteral(const Value: string): string;
begin
  Result := StringReplace(Value, '''', '''''', [rfReplaceAll]);
end;

class function TGraphClient.FindMailByInternetMessageID(
  const AccessToken, InternetMessageID: string;
  out Mail: TGraphMailInfo;
  out ErrorText: string
): Boolean;
var
  Client: THTTPClient;
  Response: IHTTPResponse;
  Root: TJSONObject;
  Values: TJSONArray;
  Obj: TJSONObject;
  NextValue: TJSONValue;
  Headers: TNetHeaders;
  Filter, URL, NextURL, ResponseBody: string;
  PageCount, MessageCount: Integer;
  OldestReceived, NewestReceived, CurrentReceived: string;
  HadNextLink: Boolean;

  function ExecutePage(const RequestURL: string; out ANextURL: string): Boolean;
  begin
    Result := False;
    ANextURL := '';
    Response := Client.Get(RequestURL, nil, Headers);
    ResponseBody := Response.ContentAsString(TEncoding.UTF8);
    Root := TJSONObject.ParseJSONValue(ResponseBody) as TJSONObject;
    try
      if Response.StatusCode <> 200 then
      begin
        ErrorText := GraphErrorText(Root, Response.StatusCode, Response.StatusText);
        Exit;
      end;
      if Root = nil then
      begin
        ErrorText := 'Die Graph-Mail-Antwort ist kein gueltiges JSON.';
        Exit;
      end;

      Values := Root.GetValue('value') as TJSONArray;
      if Values <> nil then
      begin
        Inc(PageCount);
        Inc(MessageCount, Values.Count);
        for var I := 0 to Values.Count - 1 do
        begin
          Obj := Values.Items[I] as TJSONObject;
          if Obj <> nil then
          begin
            CurrentReceived := JsonString(Obj, 'receivedDateTime');
            if CurrentReceived <> '' then
            begin
              if (NewestReceived = '') or (CurrentReceived > NewestReceived) then
                NewestReceived := CurrentReceived;
              if (OldestReceived = '') or (CurrentReceived < OldestReceived) then
                OldestReceived := CurrentReceived;
            end;
          end;
          if (Obj <> nil) and
             SameText(JsonString(Obj, 'internetMessageId'), InternetMessageID) then
          begin
            ReadMail(Obj, Mail);
            if Mail.ImmutableID = '' then
              ErrorText := 'Graph lieferte keine ImmutableID.'
            else
              Result := True;
            Exit;
          end;
        end;
      end;

      NextValue := Root.GetValue('@odata.nextLink');
      if NextValue <> nil then
      begin
        ANextURL := NextValue.Value;
        HadNextLink := True;
      end;
    finally
      Root.Free;
    end;
  end;

begin
  Mail := Default(TGraphMailInfo);
  ErrorText := '';
  Result := False;

  if AccessToken = '' then
  begin
    ErrorText := 'Kein Access Token vorhanden.';
    Exit;
  end;
  if Trim(InternetMessageID) = '' then
  begin
    ErrorText := 'Keine InternetMessageID angegeben.';
    Exit;
  end;

  SetLength(Headers, 3);
  Headers[0] := TNameValuePair.Create('Authorization', 'Bearer ' + AccessToken);
  Headers[1] := TNameValuePair.Create('Accept', 'application/json');
  Headers[2] := TNameValuePair.Create('Prefer', 'IdType="ImmutableId"');

  Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := 10000;
    Client.ResponseTimeout := 30000;
    try
      Filter := 'internetMessageId eq ''' +
        ODataStringLiteral(InternetMessageID) + '''';
      URL := 'https://graph.microsoft.com/v1.0/me/messages?' +
        '$filter=' + TURI.URLEncode(Filter) +
        '&$select=id,internetMessageId,subject,parentFolderId,receivedDateTime&$top=2';

      if ExecutePage(URL, NextURL) then
        Exit(True);
      if ErrorText <> '' then
        Exit(False);

      PageCount := 0;
      MessageCount := 0;
      OldestReceived := '';
      NewestReceived := '';
      HadNextLink := False;

      URL := 'https://graph.microsoft.com/v1.0/me/messages?' +
        '$select=id,internetMessageId,subject,parentFolderId,receivedDateTime&$top=100';

      while URL <> '' do
      begin
        NextURL := '';
        if ExecutePage(URL, NextURL) then
          Exit(True);
        if ErrorText <> '' then
          Exit(False);
        URL := NextURL;
      end;

      ErrorText :=
        'Keine Mail mit dieser InternetMessageID gefunden.' + sLineBreak +
        'Seiten geprueft: ' + IntToStr(PageCount) + sLineBreak +
        'Mails geprueft: ' + IntToStr(MessageCount) + sLineBreak +
        'Neueste ReceivedDateTime: ' + NewestReceived + sLineBreak +
        'Aelteste ReceivedDateTime: ' + OldestReceived + sLineBreak +
        'Mindestens ein @odata.nextLink: ' +
          BoolToStr(HadNextLink, True);
    except
      on E: Exception do
        ErrorText := E.Message;
    end;
  finally
    Client.Free;
  end;
end;


class function TGraphClient.TranslateExchangeID(
  const AccessToken, InputID, SourceIDType, TargetIDType: string;
  out TargetID, ErrorText: string
): Boolean;
var
  Client: THTTPClient;
  Response: IHTTPResponse;
  Root, Item: TJSONObject;
  Values: TJSONArray;
  Headers: TNetHeaders;
  RequestBody, ResponseBody: string;
  RequestStream: TStringStream;

  function JSONQuoted(const Value: string): string;
  var
    JSONString: TJSONString;
  begin
    JSONString := TJSONString.Create(Value);
    try
      Result := JSONString.ToJSON;
    finally
      JSONString.Free;
    end;
  end;

begin
  TargetID := '';
  ErrorText := '';
  Result := False;

  if (AccessToken = '') or (InputID = '') then
  begin
    ErrorText := 'Access Token oder Eingabe-ID fehlt.';
    Exit;
  end;

  RequestBody :=
    '{' +
    '"inputIds":[' + JSONQuoted(InputID) + '],' +
    '"sourceIdType":' + JSONQuoted(SourceIDType) + ',' +
    '"targetIdType":' + JSONQuoted(TargetIDType) +
    '}';

  SetLength(Headers, 3);
  Headers[0] := TNameValuePair.Create('Authorization', 'Bearer ' + AccessToken);
  Headers[1] := TNameValuePair.Create('Accept', 'application/json');
  Headers[2] := TNameValuePair.Create('Content-Type', 'application/json');

  Client := THTTPClient.Create;
  RequestStream := TStringStream.Create(RequestBody, TEncoding.UTF8);
  try
    Client.ConnectionTimeout := 10000;
    Client.ResponseTimeout := 30000;
    try
      Response := Client.Post(
        'https://graph.microsoft.com/v1.0/me/translateExchangeIds',
        RequestStream, nil, Headers
      );
      ResponseBody := Response.ContentAsString(TEncoding.UTF8);
      Root := TJSONObject.ParseJSONValue(ResponseBody) as TJSONObject;
      try
        if Response.StatusCode <> 200 then
        begin
          ErrorText := GraphErrorText(
            Root, Response.StatusCode, Response.StatusText
          ) + sLineBreak + ResponseBody;
          Exit;
        end;
        if Root = nil then
        begin
          ErrorText := 'translateExchangeIds lieferte kein gueltiges JSON.';
          Exit;
        end;

        Values := Root.GetValue('value') as TJSONArray;
        if (Values = nil) or (Values.Count <> 1) then
        begin
          ErrorText := 'translateExchangeIds lieferte nicht genau ein Ergebnis.';
          Exit;
        end;

        Item := Values.Items[0] as TJSONObject;
        if Item <> nil then
          TargetID := JsonString(Item, 'targetId');

        Result := TargetID <> '';
        if not Result then
          ErrorText :=
            'translateExchangeIds lieferte keine targetId.' + sLineBreak +
            'Graph-Antwort: ' + ResponseBody;
      finally
        Root.Free;
      end;
    except
      on E: Exception do
        ErrorText := E.Message;
    end;
  finally
    RequestStream.Free;
    Client.Free;
  end;
end;


class function TGraphClient.GetMailByImmutableID(
  const AccessToken, ImmutableID: string;
  out Mail: TGraphMailInfo;
  out ErrorText: string
): Boolean;
var
  Client: THTTPClient;
  Response: IHTTPResponse;
  Root: TJSONObject;
  Headers: TNetHeaders;
  URL: string;
begin
  Mail := Default(TGraphMailInfo);
  ErrorText := '';
  Result := False;

  if AccessToken = '' then
  begin
    ErrorText := 'Kein Access Token vorhanden.';
    Exit;
  end;
  if ImmutableID = '' then
  begin
    ErrorText := 'Keine ImmutableID angegeben.';
    Exit;
  end;

  URL := 'https://graph.microsoft.com/v1.0/me/messages/' +
    TURI.URLEncode(ImmutableID) +
    '?$select=id,internetMessageId,subject,parentFolderId,receivedDateTime';

  SetLength(Headers, 3);
  Headers[0] := TNameValuePair.Create('Authorization', 'Bearer ' + AccessToken);
  Headers[1] := TNameValuePair.Create('Accept', 'application/json');
  Headers[2] := TNameValuePair.Create('Prefer', 'IdType="ImmutableId"');

  Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := 10000;
    Client.ResponseTimeout := 30000;
    try
      Response := Client.Get(URL, nil, Headers);
      Root := TJSONObject.ParseJSONValue(
        Response.ContentAsString(TEncoding.UTF8)) as TJSONObject;
      try
        if Response.StatusCode <> 200 then
        begin
          ErrorText := GraphErrorText(Root, Response.StatusCode, Response.StatusText);
          Exit;
        end;
        if Root = nil then
        begin
          ErrorText := 'Die Graph-Mail-Antwort ist kein gueltiges JSON.';
          Exit;
        end;
        ReadMail(Root, Mail);
        Result := Mail.ImmutableID <> '';
        if not Result then
          ErrorText := 'Graph lieferte keine ImmutableID.';
      finally
        Root.Free;
      end;
    except
      on E: Exception do
        ErrorText := E.Message;
    end;
  finally
    Client.Free;
  end;
end;

end.

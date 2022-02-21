unit nosocoreunit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,IdTCPClient, IdGlobal, dateutils, strutils, MD5;

type
  TConsensus= packed record
    block : integer;
    lbhash : string;
    Diff : string;
    end;

  TSolution = Packed record
    Hash   : string;
    Target : string;
    Diff   : string;
    end;

  TConsensusData = packed record
   Value : string[40];
   count : integer;
   end;

  TNodeData = packed record
   host : string[60];
   port : integer;
   block : integer;
   Pending: integer;
   Branch : String[40];
   MNsHash : string[5];
   MNsCount : integer;
   Updated : integer;
   LBHash : String[32];
   NMSDiff : String[32];
   LBTimeEnd : Int64;
   end;

Function GetOS():string;
function UTCTime():int64;
Function Parameter(LineText:String;ParamNumber:int64):String;
Procedure ShowHelp();
Procedure ShowSettings();
Procedure LoadData();
function SaveData():boolean;
function LoadSeedNodes():integer;
Function GetConsensus():TNodeData;
Function SyncNodes():integer;
Procedure DoNothing();
Function NosoHash(source:string):string;
Function CheckHashDiff(Target,ThisHash:String):string;
function GetHashToMine():String;
Function HashMD5String(StringToHash:String):String;
Procedure SetBlockEnd(value:int64);
Function GetBlockEnd():int64;
Function ShowReadeableTime(Totalseconds:integer):string;
Procedure AddSolution(Data:TSolution);
Function SolutionsLength():Integer;
function GetSolution():TSolution;
Procedure SendSolution(Data:TSolution);
Function ResetLogs():boolean;
Procedure ToLog(Texto:String);
Procedure CheckLogs();
Function SoloMining():Boolean;

CONST
  fpcVersion = {$I %FPCVERSION%};

var
  command:string;
  MaxCPU : integer = 1;
  DataFile, LogFile, OldLogFile : TextFile;
  Counter, Counter2 : integer;

  // Arrays
  ARRAY_Nodes : array of TNodeData;
  LogLines    : array of string;
  Solutions   : Array of TSolution;

  // User options
  source : string = 'mainnet';
  address : string = 'N2kFAtGWLb57Qz91sexZSAnYwA3T7Cy';
  cpucount : integer = 1;
  autostart : boolean = false;
  minerid    : Integer = 0;

  // Critical sections
  CS_Counter      : TRTLCriticalSection;
  CS_ThisBlockEnd : TRTLCriticalSection;
  CS_MinerData    : TRTLCriticalSection;
  CS_Solutions    : TRTLCriticalSection;
  CS_Log          : TRTLCriticalSection;

  Consensus : TNodeData;
  CurrentBlockEnd : Int64 = 0;
  TargetHash : string = '00000000000000000000000000000000';
  TargetDiff : String = 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF';
  FinishMiners : boolean = true;
  PauseMiners : Boolean = false;
  ActiveMiners : integer;
  Miner_Counter : integer = 100000000;
  TestStart, TestEnd, TestTime : Int64;
  Miner_Prefix : String = '!!!!!!!!!';
  Testing : Boolean = false;
  RunMiner : Boolean = false;
  StartMiningTimeStamp:int64 = 0;
  MiningSpeed : extended = 0;
  SentThis : Integer = 0;
  GoodThis : Integer = 0;
  LastSpeedCounter : integer = 100000000;
  LastSpeedUpdate : integer = 0;
  LastSpeedHashes : integer = 0;
  LastSync : int64 = 0;
  WaitingKey : Char;
  FinishProgram : boolean = false;
  DefaultNodes : String = 'DefNodes '+
                          '23.94.21.83:8080 '+
                          '45.146.252.103:8080 '+
                          '107.172.5.8:8080 '+
                          '109.230.238.240:8080 '+
                          '172.245.52.208:8080 '+
                          '192.210.226.118:8080 '+
                          '194.156.88.117:8080';

implementation

Function GetOS():string;
Begin
Result := 'Unknown';
{$IFDEF Linux}
result := 'Linux';
{$ENDIF}
{$IFDEF WINDOWS}
result := 'Windows';
{$ENDIF}
{$IFDEF WIN32}
result := Result+'32';
{$ENDIF}
{$IFDEF WIN64}
result := Result+'64';
{$ENDIF}
End;

// Returns the UTCTime
function UTCTime():int64;
var
  G_TIMELocalTimeOffset : int64;
  GetLocalTimestamp : int64;
  UnixTime : int64;
Begin
result := 0;
G_TIMELocalTimeOffset := GetLocalTimeOffset*60;
GetLocalTimestamp := DateTimeToUnix(now);
UnixTime := GetLocalTimestamp+G_TIMELocalTimeOffset;
result := UnixTime;
End;

Function Parameter(LineText:String;ParamNumber:int64):String;
var
  Temp : String = '';
  ThisChar : Char;
  Contador : int64 = 1;
  WhiteSpaces : int64 = 0;
  parentesis : boolean = false;
Begin
while contador <= Length(LineText) do
   begin
   ThisChar := Linetext[contador];
   if ((thischar = '(') and (not parentesis)) then parentesis := true
   else if ((thischar = '(') and (parentesis)) then
      begin
      result := '';
      exit;
      end
   else if ((ThisChar = ')') and (parentesis)) then
      begin
      if WhiteSpaces = ParamNumber then
         begin
         result := temp;
         exit;
         end
      else
         begin
         parentesis := false;
         temp := '';
         end;
      end
   else if ((ThisChar = ' ') and (not parentesis)) then
      begin
      WhiteSpaces := WhiteSpaces +1;
      if WhiteSpaces > Paramnumber then
         begin
         result := temp;
         exit;
         end;
      end
   else if ((ThisChar = ' ') and (parentesis) and (WhiteSpaces = ParamNumber)) then
      begin
      temp := temp+ ThisChar;
      end
   else if WhiteSpaces = ParamNumber then temp := temp+ ThisChar;
   contador := contador+1;
   end;
if temp = ' ' then temp := '';
Result := Temp;
End;

Procedure ShowHelp();
Begin
WriteLn('');
Writeln('Available commands (Caps unsensitive)');
WriteLn('');
Writeln('help                   -> Shows this info');
Writeln('settings               -> Show the current miner settings');
Writeln('source {source}        -> The miner address');
Writeln('address {address}      -> The miner address');
Writeln('cpu {number}           -> Number of cores for Mining');
Writeln('autostart {true/false} -> Start Mining directly');
Writeln('minerid [1-8100]       -> Optional unique miner ID');
Writeln('test                   -> Speed test from 1 to Max CPUs');
Writeln('mine                   -> Start Mining with current settings');
Writeln('exit                   -> Close the app');
Writeln('');
End;

Procedure ShowSettings();
Begin
WriteLn('');
Writeln('Current settings');
WriteLn('');
WriteLn('Source    : '+source);
WriteLn('Address   : '+address);
WriteLn('CPUs      : '+CPUCount.ToString);
WriteLn('AutoStart : '+BoolToStr(AutoStart,true));
WriteLn('MinerID   : '+MinerID.ToString);
WriteLn();
End;

function SaveData():boolean;
Begin
result := true;
TRY
rewrite(datafile);
writeln(datafile,'source '+source);
writeln(datafile,'address '+Address);
writeln(datafile,'cpu '+CPUCount.ToString);
writeln(datafile,'autostart '+BoolToStr(AutoStart,true));
writeln(datafile,'minerid '+MinerID.ToString);
CloseFile(datafile);
EXCEPT ON E:EXCEPTION do
   begin
   writeln('Error opening data file: '+E.Message);
   end
END {TRY};
End;

Procedure LoadData();
var
  linea : string;
Begin
TRY
reset(datafile);
EXCEPT ON E:EXCEPTION do
   begin
   writeln('Error opening data file: '+E.Message);
   exit
   end
END {TRY};
TRY
while not eof(datafile) do
   begin
   readln(datafile,linea);
   if uppercase(Parameter(linea,0)) = 'SOURCE' then Source := Parameter(linea,1);
   if uppercase(Parameter(linea,0)) = 'ADDRESS' then Address := Parameter(linea,1);
   if uppercase(Parameter(linea,0)) = 'CPU' then CPUCount := StrToIntDef(Parameter(linea,1),1);
   if uppercase(Parameter(linea,0)) = 'AUTOSTART' then AutoStart := StrToBoolDef(Parameter(linea,1),false);
   if uppercase(Parameter(linea,0)) = 'MINERID' then MinerID := StrToIntDef(Parameter(linea,1),MinerID);
   end;
EXCEPT ON E:EXCEPTION do
   begin
   writeln('Error reading data file: '+E.Message);
   exit
   end
END {TRY};
TRY
CloseFile(datafile);
EXCEPT ON E:EXCEPTION do
   begin
   writeln('Error closing data file: '+E.Message);
   exit
   end
END {TRY};
End;

// Fill the nodes array with seed nodes data
function LoadSeedNodes():integer;
var
  counter : integer = 1;
  IsParamEmpty : boolean = false;
  ThisParam : string = '';
  ThisNode : TNodeData;
Begin
result := 0;
Repeat
   begin
   ThisParam := parameter(DefaultNodes,counter);
   if ThisParam = '' then IsParamEmpty := true
   else
      begin
      ThisNode := Default(TNodeData);
      ThisParam := StringReplace(ThisParam,':',' ',[rfReplaceAll, rfIgnoreCase]);
      ThisNode.host:=Parameter(ThisParam,0);
      ThisNode.port:=StrToIntDef(Parameter(ThisParam,1),8080);
      Insert(ThisNode,ARRAY_Nodes,length(ARRAY_Nodes));
      counter := counter+1;
      end;
   end;
until IsParamEmpty;
result := counter-1;
End;

function GetNodeStatus(Host,Port:String):string;
var
  TCPClient : TidTCPClient;
Begin
result := '';
TCPClient := TidTCPClient.Create(nil);
TCPclient.Host:=host;
TCPclient.Port:=StrToIntDef(port,8080);
TCPclient.ConnectTimeout:= 3000;
TCPclient.ReadTimeout:=3000;
TRY
TCPclient.Connect;
TCPclient.IOHandler.WriteLn('NODESTATUS');
result := TCPclient.IOHandler.ReadLn(IndyTextEncoding_UTF8);
TCPclient.Disconnect();
EXCEPT on E:Exception do
   begin
   end;
END{try};
TCPClient.Free;
End;

Function SyncNodes():integer;
var
  counter : integer = 0;
  Linea : string;
Begin
Result := 0;
For counter := 0 to length(ARRAY_Nodes)-1 do
   begin
   linea := GetNodeStatus(ARRAY_Nodes[counter].host,ARRAY_Nodes[counter].port.ToString);
   if linea <> '' then
      begin
      Result :=+1;
      ARRAY_Nodes[counter].block:=Parameter(Linea,2).ToInteger();
      ARRAY_Nodes[counter].LBHash:=Parameter(Linea,10);
      ARRAY_Nodes[counter].NMSDiff:=Parameter(Linea,11);
      ARRAY_Nodes[counter].LBTimeEnd:=StrToInt64Def(Parameter(Linea,12),0);
      end;
   end;
End;

Function GetConsensus():TNodeData;
var
  counter : integer;
  ArrT : array of TConsensusData;

   function GetHighest():string;
   var
     maximum : integer = 0;
     counter : integer;
     MaxIndex : integer = 0;
   Begin
   for counter := 0 to length(ArrT)-1 do
      begin
      if ArrT[counter].count> maximum then
         begin
         maximum := ArrT[counter].count;
         MaxIndex := counter;
         end;
      end;
   result := ArrT[MaxIndex].Value;
   End;

   Procedure AddValue(Tvalue:String);
   var
     counter : integer;
     added : Boolean = false;
     ThisItem : TConsensusData;
   Begin
   for counter := 0 to length(ArrT)-1 do
      begin
      if Tvalue = ArrT[counter].Value then
         begin
         ArrT[counter].count+=1;
         Added := true;
         end;
      end;
   if not added then
      begin
      ThisItem.Value:=Tvalue;
      ThisItem.count:=1;
      Insert(ThisITem,ArrT,length(ArrT));
      end;
   End;

Begin
SyncNodes;
result := default(TNodeData);
// Get the consensus block number
SetLength(ArrT,0);
For counter := 0 to length (ARRAY_Nodes)-1 do
   Begin
   AddValue(ARRAY_Nodes[counter].block.ToString);
   Result.block := GetHighest.ToInteger;
   End;

// Get the consensus summary
SetLength(ArrT,0);
For counter := 0 to length (ARRAY_Nodes)-1 do
   Begin
   AddValue(ARRAY_Nodes[counter].Branch);
   Result.Branch := GetHighest;
   End;

// Get the consensus pendings
SetLength(ArrT,0);
For counter := 0 to length (ARRAY_Nodes)-1 do
   Begin
   AddValue(ARRAY_Nodes[counter].Pending.ToString);
   Result.Pending := GetHighest.ToInteger;
   End;

// Get the consensus LBHash
SetLength(ArrT,0);
For counter := 0 to length (ARRAY_Nodes)-1 do
   Begin
   AddValue(ARRAY_Nodes[counter].LBHash);
   Result.LBHash := GetHighest;
   End;

// Get the consensus NMSDiff
SetLength(ArrT,0);
For counter := 0 to length (ARRAY_Nodes)-1 do
   Begin
   AddValue(ARRAY_Nodes[counter].NMSDiff);
   Result.NMSDiff := GetHighest;
   End;

// Get the consensus last block time end
SetLength(ArrT,0);
For counter := 0 to length (ARRAY_Nodes)-1 do
   Begin
   AddValue(ARRAY_Nodes[counter].LBTimeEnd.ToString);
   Result.LBTimeEnd := GetHighest.ToInt64;
   End;
EnterCriticalSection(CS_MinerData);
TargetHash := Result.LBHash;
TargetDiff := Result.NMSDiff;
LeaveCriticalSection(CS_MinerData);
SetBlockEnd(Result.LBTimeEnd);
End;

Procedure DoNothing();
Begin
// Reminder for later adition
End;

Function NosoHash(source:string):string;
var
  counter : integer;
  FirstChange : array[1..128] of string;
  finalHASH : string;
  ThisSum : integer;
  charA,charB,charC,charD:integer;
  Filler : string = '%)+/5;=CGIOSYaegk';

  Function GetClean(number:integer):integer;
  Begin
  result := number;
  if result > 126 then
     begin
     repeat
       result := result-95;
     until result <= 126;
     end;
  End;

  function RebuildHash(incoming : string):string;
  var
    counter : integer;
    resultado2 : string = '';
    chara,charb, charf : integer;
  Begin
  for counter := 1 to length(incoming) do
     begin
     chara := Ord(incoming[counter]);
       if counter < Length(incoming) then charb := Ord(incoming[counter+1])
       else charb := Ord(incoming[1]);
     charf := chara+charb; CharF := GetClean(CharF);
     resultado2 := resultado2+chr(charf);
     end;
  result := resultado2
  End;

Begin
result := '';
for counter := 1 to length(source) do
   if ((Ord(source[counter])>126) or (Ord(source[counter])<33)) then
      begin
      source := '';
      break
      end;
if length(source)>63 then source := '';
repeat source := source+filler;
until length(source) >= 128;
source := copy(source,0,128);
FirstChange[1] := RebuildHash(source);
for counter := 2 to 128 do FirstChange[counter]:= RebuildHash(firstchange[counter-1]);
finalHASH := FirstChange[128];
for counter := 0 to 31 do
   begin
   charA := Ord(finalHASH[(counter*4)+1]);
   charB := Ord(finalHASH[(counter*4)+2]);
   charC := Ord(finalHASH[(counter*4)+3]);
   charD := Ord(finalHASH[(counter*4)+4]);
   thisSum := CharA+charB+charC+charD;
   ThisSum := GetClean(ThisSum);
   Thissum := ThisSum mod 16;
   result := result+IntToHex(ThisSum,1);
   end;
Result := HashMD5String(Result);
End;

Function CheckHashDiff(Target,ThisHash:String):string;
var
   counter : integer;
   ValA, ValB, Diference : Integer;
   ResChar : String;
   Resultado : String = '';
Begin
result := 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF';
for counter := 1 to 32 do
   begin
   ValA := Hex2Dec(ThisHash[counter]);
   ValB := Hex2Dec(Target[counter]);
   Diference := Abs(ValA - ValB);
   ResChar := UPPERCASE(IntToHex(Diference,1));
   Resultado := Resultado+ResChar
   end;
Result := Resultado;
End;

function GetHashToMine():String;

  function IncreaseHashSeed(Seed:string):string;
  var
    LastChar : integer;
    contador: integer;
  Begin
  LastChar := Ord(Seed[9])+1;
  Seed[9] := chr(LastChar);
  for contador := 9 downto 1 do
     begin
     if Ord(Seed[contador])>124 then
        begin
        Seed[contador] := chr(33);
        Seed[contador-1] := chr(Ord(Seed[contador-1])+1);
        end;
     end;
  seed := StringReplace(seed,'(','~',[rfReplaceAll, rfIgnoreCase]);
  result := StringReplace(seed,'_','}',[rfReplaceAll, rfIgnoreCase]);
  End;

Begin
EnterCriticalSection(CS_Counter);
Result := Miner_Prefix+IntToStr(Miner_Counter);
Miner_Counter := Miner_Counter+1;
If Miner_Counter>999999999 then
   begin
   Miner_Counter := 100000000;
   IncreaseHashSeed(Miner_Prefix);
   if Testing then FinishMiners := true;
   end;
if ( (LastSpeedUpdate+4 < UTCTime) and (not Testing) ) then
   begin
   LastSpeedUpdate := UTCTime;
   LastSpeedHashes := Miner_Counter-LastSpeedCounter;
   MiningSpeed := LastSpeedHashes / 5;
   if MiningSpeed <0 then MiningSpeed := 0;
   LastSpeedCounter := Miner_Counter;
   write(#13,Format('Age: %4d / Best: %10s / Speed: %8.2f H/s / %d/%d',[UTCTime-Consensus.LBTimeEnd,Copy(TargetDiff,1,10),MiningSpeed,sentthis,GoodThis]));
   end;
LeaveCriticalSection(CS_Counter);
End;

Function HashMD5String(StringToHash:String):String;
Begin
result := Uppercase(MD5Print(MD5String(StringToHash)));
end;

Procedure SetBlockEnd(value:int64);
Begin
EnterCriticalSection(CS_ThisBlockEnd);
CurrentBlockEnd := value;
LeaveCriticalSection(CS_ThisBlockEnd);
End;

Function GetBlockEnd():int64;
Begin
EnterCriticalSection(CS_ThisBlockEnd);
result := CurrentBlockEnd;
LeaveCriticalSection(CS_ThisBlockEnd);
End;

Function ShowReadeableTime(Totalseconds:integer):string;
var
  days,hours,minutes,seconds, remain : integer;
Begin
Days := Totalseconds div 86400;
remain := Totalseconds mod 86400;
hours := remain div 3600;
remain := remain mod 3600;
minutes := remain div 60;
remain := remain mod 60;
seconds := remain;
if Days > 0 then Result:= Format('%dd %.2d:%.2d:%.2d', [Days, Hours, Minutes, Seconds])
else Result:= Format('%.2d:%.2d:%.2d', [Hours, Minutes, Seconds]);
End;

Procedure AddSolution(Data:TSolution);
Begin
EnterCriticalSection(CS_Solutions);
if SoloMining then
   begin
   if length(Solutions) = 0 then Insert(Data,Solutions,length(Solutions))
   else
      begin
      If Data.Diff<Solutions[0].Diff then
         Solutions[0] := Data;
      end;
   end
else
   begin
   Insert(Data,Solutions,length(Solutions));
   end;
LeaveCriticalSection(CS_Solutions);
End;

Function SolutionsLength():Integer;
Begin
EnterCriticalSection(CS_Solutions);
Result := length(Solutions);
LeaveCriticalSection(CS_Solutions);
End;

function GetSolution():TSolution;
Begin
result := Default(TSolution);
EnterCriticalSection(CS_Solutions);
if length(Solutions)>0 then
   begin
   result := Solutions[0];
   delete(Solutions,0,1);
   end;
LeaveCriticalSection(CS_Solutions);
End;

Procedure SendSolution(Data:TSolution);
var
  TCPClient : TidTCPClient;
  Node,port : integer;
  Host : string;
  Resultado : string;
  Trys : integer = 0;
  Success, WasGood : boolean;
  NewDiff : String;
Begin
Node := Random(LEngth(Array_Nodes));
Host := Array_Nodes[Node].host;
Port := Array_Nodes[Node].port;
TCPClient := TidTCPClient.Create(nil);
TCPclient.Host:=host;
TCPclient.Port:=port;
TCPclient.ConnectTimeout:= 3000;
TCPclient.ReadTimeout:=3000;
REPEAT
Success := false;
Trys :=+1;
TRY
TCPclient.Connect;
TCPclient.IOHandler.WriteLn('BESTHASH 1 2 3 4 '+address+' '+Data.Hash+' '+IntToStr(Consensus.block+1)+' '+UTCTime.ToString);
Resultado := TCPclient.IOHandler.ReadLn(IndyTextEncoding_UTF8);
TCPclient.Disconnect();
Success := true;
EXCEPT on E:Exception do
   begin
   Success := false;
   end;
END{try};
UNTIL ((Success) or (Trys = 5));
TCPClient.Free;
If success then
   begin
   SentThis := SentThis+1;
   NewDiff := Parameter (Resultado,1);
   If ((NewDiff<Targetdiff) and (length(NewDiff)= 32)) then
      begin
      EnterCriticalSection(CS_MinerData);
      TargetDiff := NewDiff;
      LeaveCriticalSection(CS_MinerData);
      end;
   WasGood := StrToBoolDef(Parameter(Resultado,0),false);
   if WasGood then GoodThis := GoodThis+1;
   end;
End;

Function SoloMining():Boolean;
Begin
Result := true;
if Uppercase(Source)<> 'MAINNET' then result := false;
End;

Procedure ToLog(Texto:String);
Begin
EnterCriticalSection(CS_Log);
Insert(Texto,LogLines,Length(LogLines));
LeaveCriticalSection(CS_Log);
End;

Function ResetLogs():boolean;
var
  ThisLine : string;
Begin
result := true;
TRY
If not FileExists('oldlogs.txt') then
   Begin
   Rewrite(OldLogFile);
   CloseFile(OldLogFile);
   end;
If not FileExists('log.txt') then
   Begin
   Rewrite(logfile);
   CloseFile(logfile);
   end;
Reset(logfile);
Append(OldLogFile);
While not Eof(LogFile) do
   begin
   ReadLn(LogFile,ThisLine);
   WriteLn(OldLogFile,ThisLine);
   end;
CloseFile(LogFile);
CloseFile(OldLogFile);
Rewrite(LogFile);
CloseFile(LogFile);
EXCEPT ON E:Exception do Result := false;
END {Try};
End;

Procedure CheckLogs();
Begin
EnterCriticalSection(CS_Log);
If length(LogLines) > 0 then
   begin
   Reset(LogFile);
   While Length(LogLines)>0 do
      begin
      WriteLn(LogFile,DateToStr(now)+' '+LogLines[0]);
      Delete(LogLines,0,1);
      end;
   CloseFile(LogFile);
   end;
LeaveCriticalSection(CS_Log);
End;

END.// END UNIT


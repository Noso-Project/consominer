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
function SaveData(address:string;cpucount:integer;autostart, usegui:boolean):boolean;
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

var
  ARRAY_Nodes : array of TNodeData;
  CS_Counter      : TRTLCriticalSection;
  CS_ThisBlockEnd : TRTLCriticalSection;
  CS_MinerData    : TRTLCriticalSection;
  Consensus : TNodeData;
  CurrentBlockEnd : Int64 = 0;
  TargetHash : string = '00000000000000000000000000000000';
  TargetDiff : String = 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF';
  FinishMiners : boolean = true;
  ActiveMiners : integer;
  Miner_Counter : integer = 100000000;
  TestStart, TestEnd, TestTime : Int64;
  Miner_Prefix : String = '!!!!!!!!!';
  Testing : Boolean = false;
  RunMiner : Boolean = false;
  StartMinningTimeStamp:int64 = 0;
  MinningSpeed : extended = 0;
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
var
  bitness : string='';
  Function Is64Bit: Boolean;
  Begin
    Result:= SizeOf(Pointer) > 4;
  End;
Begin
{$IFDEF Linux}
result := 'Linux';
{$ENDIF}
{$IFDEF WINDOWS}
result := 'Windows';
{$ENDIF}
{$IFDEF WIN32}
bitness := '32';
{$ENDIF}
{$IFDEF WIN64}
bitness := '64';
{$ENDIF}
//Result := Result+Bitness;
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

function SaveData(address:string;cpucount:integer;autostart,usegui:boolean):boolean;
var
  datafile : textfile;
Begin
result := true;
Assignfile(datafile, 'consominer.cfg');
rewrite(datafile);
writeln(datafile,'address '+address);
writeln(datafile,'cpu '+cpucount.ToString);
writeln(datafile,'autostart '+BoolToStr(autostart,true));
writeln(datafile,'usegui '+BoolToStr(usegui,true));
CloseFile(datafile);
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
//result := default(TNodeData);
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
  charA,charB,charC,charD, CharE, CharF, CharG, CharH:integer;
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
   ThisChar : string = '';
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
   MinningSpeed := LastSpeedHashes / 5;
   LastSpeedCounter := Miner_Counter;
   write(#13,Format('Age: %4d / Best: %10s / Speed: %5.2f H/s',[UTCTime-Consensus.LBTimeEnd,Copy(TargetDiff,1,10),MinningSpeed]));
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

END.// END UNIT


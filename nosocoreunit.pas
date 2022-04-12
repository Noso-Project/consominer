unit nosocoreunit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,IdTCPClient, IdGlobal, dateutils, strutils, MD5 ;

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

  TPayment       = packed record
   block    : integer;
   ammount  : int64;
   OrderID  : string[60];
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
   LBMiner   : String;
   end;

  DivResult = packed record
     cociente : string[255];
     residuo : string[255];
     end;

Function GetOS():string;
function UTCTime():int64;
Function Parameter(LineText:String;ParamNumber:int64):String;
Procedure ShowHelp();
Procedure ShowSettings();
Procedure LoadData();
function SaveData():boolean;
Procedure createpaymentsfile();
function LoadLastPayment():TPayment;
Procedure InsertNewPayment(paydata:TPayment);
Function LoadSources():integer;
function LoadSeedNodes():integer;
Function GetConsensus():TNodeData;
Function CheckSource():Boolean;
Function GetPoolData(IpandPor:String):String;
Function SyncNodes():integer;
Procedure DoNothing();
Function NosoHashOld(source:string):string;
Function CheckHashDiff(Target,ThisHash:String):string;
Function HashMD5String(StringToHash:String):String;
Function UpTime():string;
Procedure AddSolution(Data:TSolution);
Function SolutionsLength():Integer;
function GetSolution():TSolution;
Procedure PushSolution(Data:TSolution);
Procedure SubmitPoolShare(Data:TSolution);
Procedure SendSolution(Data:TSolution);
Function ResetLogs():boolean;
Procedure ToLog(Texto:String);
Procedure CheckLogs();
Function SoloMining():Boolean;
function GetPrefix(NumberID:integer):string;
Function BlockAge():integer;
Procedure AddIntervalHashes(hashes:int64);
function GetTotalHashes : integer;
Procedure ResetIntervalHashes();
Procedure SetBlockTimeStart(TValue:int64);
Function GetBlockTimeStart():Int64;
function IsValidHashAddress(Address:String):boolean;
function IsValid58(base58text:string):boolean;
function BMDecTo58(numero:string):string;
function BMB58resumen(numero58:string):string;
Function BMDividir(Numero1,Numero2:string):DivResult;
function ClearLeadingCeros(numero:string):string;
Procedure SetOMT(value:integer);
Procedure DecreaseOMT();
Function GetOMTValue():Integer;
function Int2Curr(Value: int64): string;
Function HashrateToShow(speed:int64):String;

CONST
  fpcVersion = {$I %FPCVERSION%};
  AppVersion = '0.67';
  MaxDiff    = 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF';
  HasheableChars = '!"#$%&'#39')*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~';
  B58Alphabet : string = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

var
  command:string;
  MaxCPU : integer = 1;
  CPUsToUse : integer = 0;
  DataFile, LogFile, OldLogFile, PaysFile : TextFile;
  Counter, Counter2 : integer;

  // Arrays
  ARRAY_Nodes : array of TNodeData;
  LogLines    : array of string;
  Solutions   : Array of TSolution;
  RejectedSols: Array of TSolution;

  // User options
  source : string = 'mainnet';
  address : string = 'N2kFAtGWLb57Qz91sexZSAnYwA3T7Cy';
  cpucount : integer = 1;
  autostart : boolean = false;
  minerid : Integer = 0;

  LastSourceTry : Integer = 0;
  ArrSources : Array of string;

  // Critical sections
  CS_MinerThreads   : TRTLCriticalSection;
  CS_MinerData      : TRTLCriticalSection;
  CS_Solutions      : TRTLCriticalSection;
  CS_Log            : TRTLCriticalSection;
  CS_Interval       : TRTLCriticalSection;
  CS_BlockTimeStart : TRTLCriticalSection;

  // Mining
  MAINPREFIX : String = '';
  MAINBALANCE : int64;
  PoolBALANCE : int64 = 0;
  PoolTillPayment : integer = 0;
  PoolHashRate    : int64  = 0;
  PoolLastPayment : TPayment;
  BalanceToShow : String ='';
  MiningAddress : String = '';
  ThreadsIntervalHashes : int64 = 0;
  OpenThreads : integer = 0;
  MyLastMinedBlock : integer = 0;
  TotalMinedBlocks : integer = 0;
  SourceStr   : string;
  SyncErrorStr   : String = '';
  Consensus : TNodeData;
  CurrentBlockEnd : Int64 = 0;
  CurrentBlock : integer = 0;
  NewBlock     : boolean = false;
  OpenMinerThreads : Integer = 0;                   {CS Protected}
  TargetHash : string = '00000000000000000000000000000000';
  TargetDiff : String = MaxDiff;
  FinishMiners : boolean = true;
  PauseMiners : Boolean = false;
  TestStart, TestEnd, TestTime : Int64;
  Miner_Prefix : String = '!!!!!!!!!';
  Testing : Boolean = false;
  RunMiner : Boolean = false;
  StartMiningTimeStamp:int64 = 0;
  MiningSpeed : extended = 0;
  SentThis : Integer = 0;
  GoodThis : Integer = 0;
  GoodTotal : Integer = 0;
  LastSpeedCounter : integer = 100000000;
  LastSpeedUpdate : integer = 0;
  LastSpeedHashes : integer = 0;
  BlockTimeStart  : int64 = 1;
  LastSync : int64 = 0;
  WaitingKey : Char;
  FinishProgram : boolean = false;
  DefaultNodes : String = 'DefNodes '+
                          '23.94.21.83:8080 '+
                          '45.146.252.103:8080 '+
                          '109.230.238.240:8080 '+
                          '194.156.88.117:8080 '+
                          '107.175.59.177:8080 '+
                          '107.172.193.176:8080 '+
                          '107.175.194.151:8080 '+
                          '192.3.73.184:8080';

implementation

Function GetOS():string;
Begin
Result := 'Unknown';
{$IFDEF UNIX}
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
Writeln('source {source}        -> Source information for the miner');
Writeln('address {address}      -> The miner address (not custom)');
Writeln('cpu {number}           -> Number of cores for Mining');
Writeln('autostart {true/false} -> Start Mining directly');
Writeln('minerid [0-8100]       -> Optional unique miner ID');
Writeln('test [cpus]            -> Speed test from 1 to MaxCPUs or cpus');
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

Procedure createpaymentsfile();
Begin
TRY
rewrite(PaysFile);
CloseFile(PaysFile);
EXCEPT ON E:EXCEPTION do
   begin
   writeln('Error creating payments file: '+E.Message);
   Halt(1);
   end
END {TRY};
End;

function LoadLastPayment():TPayment;
var
  lastLine : string;
Begin
Result := Default(TPayment);
reset(PaysFile);
while not eof(PaysFile) do
   begin
   ReadLn(PaysFile,LastLine)
   end;
Closefile(PaysFile);
Result.block:=StrToIntDef(Parameter(LastLine,0),0);
Result.ammount:=StrToInt64Def(Parameter(LastLine,1),0);
Result.OrderID:=Parameter(LastLine,2);
End;

Procedure InsertNewPayment(paydata:TPayment);
Begin
append(PaysFile);
Writeln(PaysFile,format('%d %d %s',[PayData.block,PayData.ammount,payData.OrderID]));
CloseFile(PaysFile);
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
   if uppercase(Parameter(linea,0)) = 'SOURCE' then Source := Copy(linea,8,length(linea));
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

Function LoadSources():integer;
var
  ThisSource : String;
  Counter : integer = 0;
Begin
Result := 0;
SetLEngth(ArrSources,0);
Repeat
   begin
   ThisSource := Parameter(Source,counter);
   If ThisSource<> '' then
      begin
      Insert(ThisSource,ArrSources,length(ArrSources));
      Result := Result +1;
      end;
   Counter := counter+1;
   end;
until ThisSource = '';
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
      Result :=Result+1;
      ARRAY_Nodes[counter].block:=Parameter(Linea,2).ToInteger();
      ARRAY_Nodes[counter].LBHash:=Parameter(Linea,10);
      ARRAY_Nodes[counter].NMSDiff:=Parameter(Linea,11);
      ARRAY_Nodes[counter].LBTimeEnd:=StrToInt64Def(Parameter(Linea,12),0);
      ARRAY_Nodes[counter].LBMiner:=Parameter(Linea,13);
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
result := default(TNodeData);
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

// Get the consensus last block Miner
SetLength(ArrT,0);
For counter := 0 to length (ARRAY_Nodes)-1 do
   Begin
   AddValue(ARRAY_Nodes[counter].LBMiner);
   Result.LBMiner := GetHighest;
   End;

//Write(format('(%d - %d)',[Result.block, CurrentBlock]));

if Result.block > CurrentBlock then
   begin
   EnterCriticalSection(CS_MinerData);
   if ((Result.LBMiner = Address) and (CurrentBlock<>0) and (Result.block<>MyLastMinedBlock)) then
      begin
      MyLastMinedBlock := Result.block;
      TotalMinedBlocks := TotalMinedBlocks+1;
      WriteLn(#13,'*************************');
      WriteLn('* You mined block '+MyLastMinedBlock.ToString+' *');
      WriteLn('*************************');
      ToLog('Mined block '+MyLastMinedBlock.ToString);
      end
   else WriteLn(#13,Format('Block : %d / Miner : %s',[Result.block,Result.LBMiner]));
   TargetHash := Result.LBHash;
   TargetDiff := Result.NMSDiff;
   CurrentBlock := Result.block;
   NewBlock := true;
   LeaveCriticalSection(CS_MinerData);
   end;

End;

Function CheckSource():Boolean;
var
  ReachedNodes : integer = 0;
  ThisSource   : String;
  PoolString : String ='';
  PoolPayStr : string = '';
  PoolPayData : TPayment;
Begin
Result := False;
LastSourceTry := LastSourceTry+1;
if LastSourceTry<0 then LastSourceTry := 0;
if LastSourceTry>=length(ArrSources) then LastSourceTry := 0;
ThisSource := ArrSources[LastSourceTry];
If UpperCase(ThisSource) = 'MAINNET' then
   begin
   writeln();
   ReachedNodes := SyncNodes;
   if ReachedNodes >= (Length(array_nodes) div 2) then
      begin
      Consensus := GetConsensus;
      SourceStr := ThisSource;
      SyncErrorStr := '';
      MAINPREFIX := '';
      MiningAddress := Address;
      result := true;
      LastSourceTry := -1;
      ToLog('-> Block '+Consensus.block.ToString+' to mainnet');
      end
   else
      begin
      if not runminer then WriteLn(Format('Synced failed %d/%d',[ReachedNodes,Length(array_nodes)]))
      else SyncErrorStr := 'Connection error. Check your internet connection                               ';
      end;
   end
else
   begin
   PoolString := GetPoolData(ThisSource);
   if PoolString<> 'ERROR' then // Pool reached
      begin
      SourceStr := ThisSource;
      SyncErrorStr := '';
      LastSourceTry := -1;
      //ToLog(Parameter(PoolString,5)+'<>'+CurrentBlock.ToString); // debug only
      if StrToIntDef(Parameter(PoolString,5),0) > CurrentBlock then
         begin
         NewBlock := true;
         result := true;
         MAINPREFIX := Parameter(PoolString,1);
         MiningAddress := Parameter(PoolString,2);
            EnterCriticalSection(CS_MinerData);
            TargetHash := Parameter(PoolString,4);
            TargetDiff := Parameter(PoolString,3);
            CurrentBlock := StrToIntDef(Parameter(PoolString,5),0);
            PoolBALANCE     := StrToInt64Def(Parameter(PoolString,6),0);
            PoolTillPayment := StrToIntDef(Parameter(PoolString,7),0);
            PoolPayStr     := Parameter(PoolString,8);
               PoolPayStr  := StringReplace(PoolPayStr,':',' ',[rfReplaceAll, rfIgnoreCase]);
               PoolPayData.block:=StrToIntDef(Parameter(PoolPayStr,0),0);
               PoolPayData.ammount:=StrToInt64Def(Parameter(PoolPayStr,1),0);
               PoolPayData.OrderID:=Parameter(PoolPayStr,2);
               if PoolPayData.OrderID <> PoolLastPayment.OrderID then
                  begin
                  PoolLastPayment := PoolPayData;
                  InsertNewPayment(PoolLastPayment);
                  Writeln('*** NEW POOL PAYMENT ***')
                  end;
            PoolHashRate    := StrToInt64Def(Parameter(PoolString,9),0);
            NewBlock := true;
            LeaveCriticalSection(CS_MinerData);
            ToLog('-> Block '+CurrentBlock.ToString+' to '+SourceStr);
         end;
      end
   else
      begin
      if not runminer then writeln(ThisSource+' unreacheable')
      else SyncErrorStr := 'Connection error. Check your internet connection                               ';
      end;
   end;
End;

Function GetPoolData(IpandPor:String):String;
var
  TCPClient : TidTCPClient;
  ResultLine : String = '';
Begin
Result := 'ERROR';
ResultLine := '';
TCPClient := TidTCPClient.Create(nil);
IpandPor := StringReplace(IpandPor,':',' ',[rfReplaceAll, rfIgnoreCase]);
TCPclient.Host:=Parameter(IpandPor,0);
TCPclient.Port:=StrToIntDef(Parameter(IpandPor,1),8082);
TCPclient.ConnectTimeout:= 3000;
TCPclient.ReadTimeout:=3000;
TRY
TCPclient.Connect;
TCPclient.IOHandler.WriteLn('SOURCE '+Address);
ResultLine := TCPclient.IOHandler.ReadLn(IndyTextEncoding_UTF8);
TCPclient.Disconnect();
EXCEPT on E:Exception do
   begin
   end;
END{try};
TCPClient.Free;
if Parameter(ResultLine,0)='OK' then
   begin
   Result := ResultLine;
   end;
End;

Procedure DoNothing();
Begin
// Reminder for later adition
End;

Function NosoHashOld(source:string):string;
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
   Resultado := Resultado+ResChar;
   end;
Result := Resultado;
End;

Function HashMD5String(StringToHash:String):String;
Begin
result := Uppercase(MD5Print(MD5String(StringToHash)));
end;

Function UpTime():string;
var
  TotalSeconds,days,hours,minutes,seconds, remain : integer;
Begin
Totalseconds := UTCTime-StartMiningTimeStamp;
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

Procedure PushSolution(Data:TSolution);
Begin
If SoloMining then SendSolution(Data)
else SubmitPoolShare(Data);
End;

Procedure SubmitPoolShare(Data:TSolution);
var
  TCPClient  : TidTCPClient;
  IpandPor   : String = '';
  ResultLine : String = '';
  Trys       : integer = 0;
  Success    : boolean;
Begin
ResultLine := '';
TCPClient := TidTCPClient.Create(nil);
IpandPor := StringReplace(SourceStr,':',' ',[rfReplaceAll, rfIgnoreCase]);
TCPclient.Host:=Parameter(IpandPor,0);
TCPclient.Port:=StrToIntDef(Parameter(IpandPor,1),8082);
TCPclient.ConnectTimeout:= 3000;
TCPclient.ReadTimeout:=3000;
REPEAT
Success := false;
Trys :=+1;
TRY
TCPclient.Connect;
TCPclient.IOHandler.WriteLn('SHARE '+address+' '+Data.Hash);
ResultLine := TCPclient.IOHandler.ReadLn(IndyTextEncoding_UTF8);
TCPclient.Disconnect();
Success := true;
EXCEPT on E:Exception do
   Success := false;
END{try};
UNTIL ((Success) or (Trys = 5));
TCPClient.Free;
if Success then
   begin
   if resultLine = 'True' then
      begin
      GoodThis := GoodThis+1;
      ToLog('Submited share: '+Data.Diff);
      end
   else
      begin
      ToLog('Rejected share: '+ResultLine);
      end;
   end
else // Not send
   begin
   ToLog('Unable to send solution to '+SourceStr);
   SyncErrorStr := 'Connection error. Check your internet connection                               ';
   Insert(Data,RejectedSols,Length(RejectedSols));
   end;
End;

Procedure SendSolution(Data:TSolution);
var
  TCPClient : TidTCPClient;
  Node : integer;
  Resultado : string;
  Trys : integer = 0;
  Success, WasGood : boolean;
  NewDiff : String;
  ErrorCode : integer = 0;
Begin
Node := Random(LEngth(Array_Nodes));
TCPClient := TidTCPClient.Create(nil);
TCPclient.ConnectTimeout:= 3000;
TCPclient.ReadTimeout:=3000;
REPEAT
Node := Node+1; If Node >= LEngth(Array_Nodes) then Node := 0;
TCPclient.Host:=Array_Nodes[Node].host;
TCPclient.Port:=Array_Nodes[Node].port;
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
   if WasGood then
      begin
      GoodTotal := GoodTotal+1;
      GoodThis := GoodThis+1;
      ToLog('Submited solution: '+Data.Diff);
      end
   else
      begin
      ErrorCode := StrToIntDef(Parameter(Resultado,2),0);
      ToLog('Rejected Solution: '+ErrorCode.ToString);
      end;
   end
else
   begin
   ToLog('Unable to send solution');
   SyncErrorStr := 'Connection error. Check your internet connection                               ';
   Insert(Data,RejectedSols,Length(RejectedSols));
   end;
End;

Function SoloMining():Boolean;
Begin
Result := true;
if Uppercase(SourceStr)<> 'MAINNET' then result := false;
End;

Procedure ToLog(Texto:String);
Begin
EnterCriticalSection(CS_Log);
Insert(DateTimeToStr(now)+' '+Texto,LogLines,Length(LogLines));
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
EXCEPT ON E:Exception do
   Result := false;
END {Try};
End;

Procedure CheckLogs();
Begin
If length(LogLines) > 0 then
   begin
   EnterCriticalSection(CS_Log);
   TRY
   Append(LogFile);
   While Length(LogLines)>0 do
      begin
      WriteLn(LogFile,LogLines[0]);
      Delete(LogLines,0,1);
      end;
   CloseFile(LogFile);
   EXCEPT ON E:EXCEPTION DO
      //WriteLn(E.Message);
   END; {Try}
   LeaveCriticalSection(CS_Log);
   end;
End;

function GetPrefix(NumberID:integer):string;
var
  firstchar, secondchar : integer;
  HashChars : integer;
Begin
HashChars :=  length(HasheableChars)-1;
firstchar := NumberID div HashChars;
secondchar := NumberID mod HashChars;
result := HasheableChars[firstchar+1]+HasheableChars[secondchar+1];
End;

Function BlockAge():integer;
Begin
Result := UTCTime mod 600;
End;

Procedure AddIntervalHashes(hashes:int64);
Begin
EnterCriticalSection(CS_Interval);
ThreadsIntervalHashes := ThreadsIntervalHashes+hashes;
LeaveCriticalSection(CS_Interval);
End;

function GetTotalHashes : integer;
Begin
EnterCriticalSection(CS_Interval);
Result := ThreadsIntervalHashes;
LeaveCriticalSection(CS_Interval);
End;

Procedure ResetIntervalHashes();
Begin
EnterCriticalSection(CS_Interval);
ThreadsIntervalHashes := 0;
LeaveCriticalSection(CS_Interval);
End;

Procedure SetBlockTimeStart(TValue:int64);
Begin
EnterCriticalSection(CS_BlockTimeStart);
BlockTimeStart := UTCTime;
LeaveCriticalSection(CS_BlockTimeStart);
End;

Function GetBlockTimeStart():Int64;
Begin
EnterCriticalSection(CS_BlockTimeStart);
Result := BlockTimeStart;
LeaveCriticalSection(CS_BlockTimeStart);
End;

// Checks if a string is a valid address hash
function IsValidHashAddress(Address:String):boolean;
var
  OrigHash : String;
  Clave:String;
Begin
result := false;
if ((length(address)>20) and (address[1] = 'N')) then
   begin
   OrigHash := Copy(Address,2,length(address)-3);
   if IsValid58(OrigHash) then
      begin
      Clave := BMDecTo58(BMB58resumen(OrigHash));
      OrigHash := 'N'+OrigHash+clave;
      if OrigHash = Address then result := true else result := false;
      end;
   end
End;

function IsValid58(base58text:string):boolean;
var
  counter : integer;
Begin
result := true;
if length(base58text) > 0 then
   begin
   for counter := 1 to length(base58text) do
      begin
      if pos (base58text[counter],B58Alphabet) = 0 then
         begin
         result := false;
         break;
         end;
      end;
   end
else result := false;
End;

// CONVERTS A DECIMAL VALUE TO A BASE58 STRING
function BMDecTo58(numero:string):string;
var
  decimalvalue : string;
  restante : integer;
  ResultadoDiv : DivResult;
  Resultado : string = '';
Begin
decimalvalue := numero;
while length(decimalvalue) >= 2 do
   begin
   ResultadoDiv := BMDividir(decimalvalue,'58');
   DecimalValue := Resultadodiv.cociente;
   restante := StrToInt(ResultadoDiv.residuo);
   resultado := B58Alphabet[restante+1]+resultado;
   end;
if StrToInt(decimalValue) >= 58 then
   begin
   ResultadoDiv := BMDividir(decimalvalue,'58');
   DecimalValue := Resultadodiv.cociente;
   restante := StrToInt(ResultadoDiv.residuo);
   resultado := B58Alphabet[restante+1]+resultado;
   end;
if StrToInt(decimalvalue) > 0 then resultado := B58Alphabet[StrToInt(decimalvalue)+1]+resultado;
result := resultado;
End;

// RETURN THE SUMATORY OF A BASE58
function BMB58resumen(numero58:string):string;
var
  counter, total : integer;
Begin
total := 0;
for counter := 1 to length(numero58) do
   begin
   total := total+Pos(numero58[counter],B58Alphabet)-1;
   end;
result := IntToStr(total);
End;

// DIVIDES TO NUMBERS
Function BMDividir(Numero1,Numero2:string):DivResult;
var
  counter : integer;
  cociente : string = '';
  long : integer;
  Divisor : Int64;
  ThisStep : String = '';
Begin
long := length(numero1);
Divisor := StrToInt64(numero2);
for counter := 1 to long do
   begin
   ThisStep := ThisStep + Numero1[counter];
   if StrToInt(ThisStep) >= Divisor then
      begin
      cociente := cociente+IntToStr(StrToInt(ThisStep) div Divisor);
      ThisStep := (IntToStr(StrToInt(ThisStep) mod Divisor));
      end
   else cociente := cociente+'0';
   end;
result.cociente := ClearLeadingCeros(cociente);
result.residuo := ClearLeadingCeros(thisstep);
End;

// REMOVES LEFT CEROS
function ClearLeadingCeros(numero:string):string;
var
  count : integer = 0;
  movepos : integer = 0;
Begin
result := '';
if numero[1] = '-' then movepos := 1;
for count := 1+movepos to length(numero) do
   begin
   if numero[count] <> '0' then result := result + numero[count];
   if ((numero[count]='0') and (length(result)>0)) then result := result + numero[count];
   end;
if result = '' then result := '0';
if ((movepos=1) and (result <>'0')) then result := '-'+result;
End;

Procedure SetOMT(value:integer);
Begin
EnterCriticalSection(CS_MinerThreads);
OpenMinerThreads := value;
LeaveCriticalSection(CS_MinerThreads);
End;

Procedure DecreaseOMT();
Begin
EnterCriticalSection(CS_MinerThreads);
OpenMinerThreads := OpenMinerThreads-1;
{
write(format('%2s',[IntToStr(OpenMinerThreads)]));
write(#08#08);
}
LeaveCriticalSection(CS_MinerThreads);
End;

Function GetOMTValue():Integer;
Begin
EnterCriticalSection(CS_MinerThreads);
Result := OpenMinerThreads;
LeaveCriticalSection(CS_MinerThreads);
End;

function Int2Curr(Value: int64): string;
begin
Result := IntTostr(Abs(Value));
result :=  AddChar('0',Result, 9);
Insert('.',Result, Length(Result)-7);
If Value <0 THen Result := '-'+Result;
end;

Function HashrateToShow(speed:int64):String;
Begin
if speed>1000000000 then result := FormatFloat('0.00',speed/1000000000)+' Gh/s'
else if speed>1000000 then result := FormatFloat('0.00',speed/1000000)+' Mh/s'
else if speed>1000 then result := FormatFloat('0.00',speed/1000)+' Kh/s'
else result := speed.ToString+' h/s'
End;

INITIALIZATION
InitCriticalSection(CS_MinerThreads);
InitCriticalSection(CS_BlockTimeStart);


FINALIZATION
DoneCriticalSection(CS_MinerThreads);
DoneCriticalSection(CS_BlockTimeStart);

END.// END UNIT


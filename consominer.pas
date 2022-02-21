program consominer;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
   cthreads,
  {$ENDIF}
  Classes, sysutils, nosocoreunit, strutils , UTF8Process
  { you can add units after this };

Type
  TMinerThread = class(TThread)
    protected
      procedure Execute; override;
    public
      Constructor Create(CreateSuspended : boolean);
    end;

  TMainThread = class(TThread)
    protected
      procedure Execute; override;
    public
      Constructor Create(CreateSuspended : boolean);
    end;

var

  ArrMiners : Array of TMinerThread;
  MainThread : TMainThread;
  CPUspeed: extended;
  HashesToTest : integer = 5000;
  FirstRun : boolean = true;

Function ActiveMinersCount():Integer;
var
  Number: Integer;
Begin
Result := 0;
for Number:= 0 to Length(ArrMiners)-1 do
   if Assigned(ArrMiners[Number]) then Result := Result+1;
End;

constructor TMinerThread.Create(CreateSuspended : boolean);
Begin
inherited Create(CreateSuspended);
FreeOnTerminate := True;
End;

constructor TMainThread.Create(CreateSuspended : boolean);
Begin
inherited Create(CreateSuspended);
FreeOnTerminate := True;
End;

procedure TMinerThread.Execute;
var
  BaseHash, ThisHash, ThisDiff : string;
  ThisSolution : TSolution;
Begin
While not FinishMiners do
   begin
   BaseHash := GetHashToMine;
   ThisHash := NosoHash(BaseHash+Address);
   ThisDiff := CheckHashDiff(TargetHash,ThisHash);
   if ThisDiff<TargetDiff then
      begin
      ThisSolution.Target:=TargetHash;
      ThisSolution.Hash  :=BaseHash;
      ThisSolution.Diff  :=ThisDiff;
      AddSolution(ThisSolution);
      end;
   end;
End;

procedure TMainThread.Execute;
var
  currentblock : integer;
Begin
While not FinishProgram do
   begin
   CheckLogs;
   if runminer then
      begin
      OpenThreads := ActiveMinersCount;
      if SolutionsLength>0 then
         begin
         Repeat
         PushSolution(GetSolution);
         until solutionslength = 0 ;
         end;
      Currentblock := Consensus.block;
      if ( (UTCTime >= GetBlockEnd-15) and (TargetDiff<MaxDiff) ) then
         Begin
         FinishMiners := true;
         PauseMiners := true;
         end;
      if ( (UTCTime >= GetBlockEnd+10) and (LastSync+10<UTCTime) ) then
         begin
         LastSync := UTCTime;
         CheckSource;
         if Consensus.block <> CurrentBlock then
            begin
            GoodThis := 0;
            SentThis := 0;
            Miner_Counter := 100000000;
            LastSpeedCounter := 100000000;
            FinishMiners := false;
            PauseMiners := false;
            for counter2 := 1 to CPUCount do
                begin
                ArrMiners[counter2-1] := TMinerThread.Create(true);
                ArrMiners[counter2-1].FreeOnTerminate:=true;
                ArrMiners[counter2-1].Start;
                end;
            writeln(#13,'-----------------------------------------------------------------------------');
            Writeln(Format('Block: %d / Address: %s / Cores: %d',[Consensus.block,address,cpucount]));
            Writeln(Format('%s / Target: %s / %s',[ShowReadeableTime(UTCTime-StartMiningTimeStamp),Copy(TargetHash,1,10),SourceStr]));
            end;
         end;
      if ( (LastSpeedUpdate+4 < UTCTime) and (not Testing) ) then
         begin
         LastSpeedUpdate := UTCTime;
         LastSpeedHashes := Miner_Counter-LastSpeedCounter;
         MiningSpeed := LastSpeedHashes / 5;
         if MiningSpeed <0 then MiningSpeed := 0;
         LastSpeedCounter := Miner_Counter;
         if PauseMiners then ExInfo := 'P' else ExInfo := '';
         if SyncErrorStr <> '' then write(#13,Format('%s',[SyncErrorStr]))
         else write(#13,Format('[%d]%s Age: %4d / Best: %10s / Speed: %8.2f H/s / %d/%d',[OpenThreads,ExInfo,UTCTime-Consensus.LBTimeEnd,Copy(TargetDiff,1,10),MiningSpeed,sentthis,GoodThis]));
         end;
      end;
   sleep(1000);
   end;
End;

{$R *.res}

begin
InitCriticalSection(CS_Counter);
InitCriticalSection(CS_ThisBlockEnd);
InitCriticalSection(CS_MinerData);
InitCriticalSection(CS_Solutions);
InitCriticalSection(CS_Log);
Assignfile(datafile, 'consominer.cfg');
Assignfile(logfile, 'log.txt');
Assignfile(OldLogFile, 'oldlogs.txt');
If not ResetLogs then
   begin
   writeln('Error reseting log files');
   Exit;
   end;
SetLEngth(ARRAY_Nodes,0);
SetLEngth(Solutions,0);
SetLEngth(LogLines,0);
MaxCPU:= {$IFDEF UNIX}GetSystemThreadCount{$ELSE}GetCPUCount{$ENDIF};
SetLength(ArrMiners,MaxCPU);  // Avoid overclocking
if not FileExists('consominer.cfg') then savedata();
loaddata();
LoadSeedNodes;
writeln('Consominer Nosohash 1.0');
writeln('Built using FPC '+fpcVersion);
Writeln(GetOs+' --- '+MaxCPU.ToString+' CPUs --- '+Length(array_nodes).ToString+' Nodes');
writeln('Using '+address+' with '+CPUCount.ToString+' cores');
if not autostart then writeln('Please type help to get a list of commands');
MainThread := TMainThread.Create(true);
MainThread.FreeOnTerminate:=true;
MainThread.Start;
REPEAT
   command := '';
   if FirstRun then
      begin
      FirstRun := false;
      if AutoStart then Command := 'MINE';
      end;
   if command = '' then
      begin
      write('> ');
      readln(command);
      end;
   if Uppercase(Parameter(command,0)) = 'ADDRESS' then
      begin
      address := parameter(command,1);
      savedata();
      writeln ('Mining address set to : '+address);
      end
   else if Uppercase(Parameter(command,0)) = 'CPU' then
      begin
      cpucount := StrToIntDef(parameter(command,1),CPUCount);
      savedata();
      writeln ('Mining CPUs set to : '+CPUCount.ToString);
      end
   else if Uppercase(Parameter(command,0)) = 'TEST' then
      begin
      Testing:= true;
      for counter :=1 to MaxCPU do
         begin
         write('Testing with '+counter.ToString+' CPUs: ');
         TestStart := GetTickCount64;
         FinishMiners := false;
         Miner_Counter := 1000000000-(HashesToTest*counter);
         ActiveMiners := counter;
         for counter2 := 1 to counter do
            begin
            ArrMiners[counter2-1] := TMinerThread.Create(true);
            ArrMiners[counter2-1].FreeOnTerminate:=true;
            ArrMiners[counter2-1].Start;
            end;
         REPEAT
            sleep(1)
         until FinishMiners;
         TestEnd := GetTickCount64;
         TestTime := (TestEnd-TestStart);
         CPUSpeed := HashesToTest/(testtime/1000);
         writeln(FormatFloat('0.00',CPUSpeed)+' -> '+FormatFloat('0.00',CPUSpeed*counter)+' h/s');
         end;
      Testing := false;
      end
   else if Uppercase(Parameter(command,0)) = 'EXIT' then
      begin
      DoNothing;
      end
   else if Uppercase(Parameter(command,0)) = 'AUTOSTART' then
      begin
      autostart := StrToBoolDef(parameter(command,1),autostart);
      savedata();
      writeln ('Autostart set to : '+BoolToStr(autostart,true));
      end
   else if Uppercase(Parameter(command,0)) = 'MINERID' then
      begin
      MinerID := StrToIntDef(parameter(command,1),MinerID);
      savedata();
      writeln ('MinerID set to : '+MinerID.ToString);
      end
   else if Uppercase(Parameter(command,0)) = 'MINE' then
      begin
      Repeat
         Write('Syncing...',#13);
         sleep(100);
      until CheckSource;
      Writeln(format('Block: %d / Age: %d secs / Hash: %s',[Consensus.block,UTCTime-Consensus.LBTimeEnd,Consensus.LBHash]));
      LastSync := UTCTime;
      SetBlockEnd(Consensus.LBTimeEnd+600);
      RunMiner := true;
      writeln('Mining with '+CPUcount.ToString+' CPUs');
      if SoloMining then SourceStr := 'Mainnet' else SourceStr := '?????';
      writeln('Press CTRL+C to finish');
      ToLog('********************************************************************************');
      ToLog('Mining session opened');
      FinishMiners := false;
      Miner_Counter := 1000000000;
      StartMiningTimeStamp := UTCTime;
      SentThis := 0;
      for counter2 := 1 to CPUCount do
         begin
         ArrMiners[counter2-1] := TMinerThread.Create(true);
         ArrMiners[counter2-1].FreeOnTerminate:=true;
         ArrMiners[counter2-1].Start;
         end;
      writeln('-----------------------------------------------------------------------------');
      Writeln(Format('Block: %d / Address: %s / Cores: %d',[Consensus.block,address,cpucount]));
      Writeln(Format('%s / Target: %s / %s',[ShowReadeableTime(UTCTime-StartMiningTimeStamp),Copy(TargetHash,1,10),SourceStr]));

      Repeat
      until RunMiner = false;
      end
   else if Uppercase(Parameter(command,0)) = 'HELP' then ShowHelp
   else if Uppercase(Parameter(command,0)) = 'SETTINGS' then ShowSettings
   else if Command <> '' then writeln('Invalid command');
UNTIL Uppercase(Command) = 'EXIT';
DoneCriticalSection(CS_Counter);
DoneCriticalSection(CS_ThisBlockEnd);
DoneCriticalSection(CS_MinerData);
DoneCriticalSection(CS_Solutions);
DoneCriticalSection(CS_Log);
end.// end program


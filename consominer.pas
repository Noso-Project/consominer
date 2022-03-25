program consominer;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
   cthreads,
  {$ENDIF}
  Classes, sysutils, strutils, nosocoreunit, NosoDig.Crypto, UTF8Process
  { you can add units after this };

Type
  TMinerThread = class(TThread)
    private
      TNumber:integer;
    protected
      procedure Execute; override;
    public
      Constructor Create(CreateSuspended : boolean; const Thisnumber:integer);
    end;

  TMainThread = class(TThread)
    protected
      procedure Execute; override;
    public
      Constructor Create(CreateSuspended : boolean);
    end;

var
  MainThread : TMainThread;
  CPUspeed: extended;
  HashesToTest : integer = 10000;
  FirstRun : boolean = true;
  CPUsToUse : integer = 0;
  MinerThread : TMinerThread;

Constructor TMinerThread.Create(CreateSuspended : boolean; const Thisnumber:integer);
Begin
inherited Create(CreateSuspended);
Tnumber := ThisNumber;
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
  MyID : integer;
  ThisPrefix : string = '';
  MyCounter : int64 = 100000000;
  EndThisThread : boolean = false;
  TempHashes : integer = 0;
  LastRefresh : int64 = 0;
  ThreadBest  : string = '0000FFFFFFFFFFFFFFFFFFFFFFFFFFFF';
Begin
MyID := TNumber-1;
ThisPrefix := MAINPREFIX+GetPrefix(MinerID)+GetPrefix(MyID);
ThisPrefix := AddCharR('!',ThisPrefix,9);
While ((not FinishMiners) and (not EndThisThread)) do
   begin
   BaseHash := ThisPrefix+MyCounter.ToString;
   MyCounter := MyCounter+1;TempHashes := TempHashes+1;
   ThisHash := NosoHash(BaseHash+MiningAddress);
   ThisDiff := GetHashDiff(TargetHash,ThisHash);
   if ThisDiff<ThreadBest then
      begin
      ThisSolution.Target:=TargetHash;
      ThisSolution.Hash  :=BaseHash;
      ThisSolution.Diff  :=ThisDiff;
      ThreadBest := ThisDiff;
      if not testing then AddSolution(ThisSolution);
      end;
   if not testing then
      begin
      if LastRefresh+4<UTCTime then
         begin
         AddIntervalHashes(TempHashes);
         TempHashes := 0;
         end;
      end;
   if ((MyCounter >= 100000000+HashesToTest) and (Testing)) then EndThisThread := true;
   end;
DecreaseOMT;
End;

procedure TMainThread.Execute;
Begin
While not FinishProgram do
   begin
   if runminer then
      begin
      CheckLogs;
      While Length(RejectedSols)>0 do
         begin
         write(Length(RejectedSols));
         AddSolution(RejectedSols[0]);
         Delete(RejectedSols,0,1);
         end;
      While SolutionsLength>0 do
         begin
         PushSolution(GetSolution);
         end;
      if ( (BlockAge>585) and (TargetDiff<MaxDiff) ) then
         Begin
         FinishMiners := true;
         PauseMiners := true;
         GetTotalHashes;
         end;
      if ( (BlockAge >= 10) and (LastSync+3<UTCTime) and (PauseMiners)) then
         begin
         LastSync := UTCTime;
         CheckSource;
         if NewBlock then
            begin
            NewBlock := False;
            GoodThis := 0;
            SentThis := 0;
            LastSpeedCounter := 100000000;
            FinishMiners := false;
            PauseMiners := false;
            for counter2 := 1 to CPUCount do
                begin
                MinerThread := TMinerThread.Create(true,counter2);
                MinerThread.FreeOnTerminate:=true;
                MinerThread.Start;
                Sleep(1);
                end;
            OpenThreads := CPUCount;
            writeln(#13,'--------------------------------------------------------------------');
            Writeln(Format('Block: %d / Address: %s / Cores: %d',[CurrentBlock,address,cpucount]));
            Writeln(Format('%s / Target: %s / %s / [%d]' ,[UpTime,Copy(TargetHash,1,10),SourceStr,TotalMinedBlocks]));
            end;
         end;
      if ( (LastSpeedUpdate+4 < UTCTime) and (not Testing) ) then
         begin
         MiningSpeed := GetTotalHashes / (UTCTime-LastSpeedUpdate);
         if MiningSpeed <0 then MiningSpeed := 0;
         if SyncErrorStr <> '' then write(Format(' %s',[SyncErrorStr]),#13)
         else
            begin
            if OpenThreads>0 then write(Format(' [%d] Age: %4d / Best: %10s / Speed: %8.2f H/s / {%d}',[OpenThreads,BlockAge,Copy(TargetDiff,1,10),MiningSpeed,GoodThis]),#13)
            else write(Format(' %s',['Waiting next block                                          ']),#13);
            end;
         LastSpeedUpdate := UTCTime;
         end;
      end;
   sleep(1000);
   end;
End;

{$R *.res}

BEGIN // Program Start
InitCriticalSection(CS_MinerData);
InitCriticalSection(CS_Solutions);
InitCriticalSection(CS_Log);
InitCriticalSection(CS_Interval);
Assignfile(datafile, 'consominer.cfg');
Assignfile(logfile, 'log.txt');
Assignfile(OldLogFile, 'oldlogs.txt');
Consensus := Default(TNodeData);
If not ResetLogs then
   begin
   writeln('Error reseting log files');
   Exit;
   end;
SetLEngth(ARRAY_Nodes,0);
SetLEngth(Solutions,0);
SetLEngth(RejectedSols,0);
SetLEngth(LogLines,0);
SetLEngth(ArrSources,0);
MaxCPU:= {$IFDEF UNIX}GetSystemThreadCount{$ELSE}GetCPUCount{$ENDIF};
if not FileExists('consominer.cfg') then savedata();
loaddata();
LoadSeedNodes;
writeln('Consominer Nosohash '+AppVersion);
writeln('Built using FPC '+fpcVersion);
writeln('Hashing optimizations by @Equinox');
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
      if AutoStart then //Command := 'MINE';
         begin
         if IsValidHashAddress(Address) then Command := 'MINE'
         else WriteLn('Invalid miner address');
         end;
      end;
   if command = '' then
      begin
      write('> ');
      readln(command);
      end;
   if Uppercase(Parameter(command,0)) = 'ADDRESS' then
      begin
      if IsValidHashAddress(Parameter(command,1)) then
         begin
         address := parameter(command,1);
         savedata();
         writeln ('Mining address set to : '+address);
         end
      else WriteLn('Invalid miner address');
      end
   else if Uppercase(Parameter(command,0)) = 'CPU' then
      begin
      cpucount := StrToIntDef(parameter(command,1),CPUCount);
      savedata();
      writeln ('Mining CPUs set to : '+CPUCount.ToString);
      end
   else if Uppercase(Parameter(command,0)) = 'TEST' then
      begin
      CPUsToUse := StrToIntDef(Parameter(command,1),MaxCPU);
      Testing:= true;
      for counter :=1 to CPUsToUse do
         begin
         write('Testing '+HashesToTest.toString+' hashes with '+counter.ToString+' CPUs: ');
         TestStart := GetTickCount64;
         FinishMiners := false;
         ActiveMiners := counter;
         for counter2 := 1 to counter do
            begin
            MinerThread := TMinerThread.Create(true,counter2);
            MinerThread.FreeOnTerminate:=true;
            MinerThread.Start;
            sleep(1);
            end;
         SetOMT(counter);
         REPEAT
            sleep(1)
         UNTIL GetOMTValue = 0;
         TestEnd := GetTickCount64;
         TestTime := (TestEnd-TestStart);
         CPUSpeed := HashesToTest/(testtime/1000);
         writeln('['+FormatFLoat('0.000',testtime/1000)+' sec] '+FormatFloat('0.00',CPUSpeed)+' -> '+FormatFloat('0.00',CPUSpeed*counter)+' h/s');
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
      if  StrToIntDef(parameter(command,1),-1)<0 then
         WriteLn('MinerID must be a number between 0-8100')
      else
         begin
         MinerID := StrToIntDef(parameter(command,1),MinerID);
         savedata();
         writeln ('MinerID set to : '+MinerID.ToString);
         end;
      end
   else if Uppercase(Parameter(command,0)) = 'MINE' then
      begin
      if not isvalidHashAddress(Address) then
         begin
         WriteLn('Invalid miner address');
         continue;
         end;
      if LoadSources = 0 then
         begin
         WriteLn('No sources set');
         continue;
         end
      else WriteLn('Sources found: '+Length(ArrSources).ToString);
      LastSourceTry := -1;
      ToLog('********************************************************************************');
      ToLog('Mining session opened');
      Repeat
         Write('Syncing...',#13);
         sleep(100);
      until CheckSource;
      Writeln(format('Block: %d / Age: %d secs / Hash: %s',[Consensus.block,UTCTime-Consensus.LBTimeEnd,Consensus.LBHash]));
      LastSync := UTCTime;
      RunMiner := true;
      NewBlock := false;
      Miner_Prefix := AddCharR('!',MAINPREFIX+GetPrefix(MinerID),9);
      writeln('Mining with '+CPUcount.ToString+' CPUs and Prefix '+Miner_Prefix);
      writeln('Press CTRL+C to finish');
      GetTotalHashes;
      FinishMiners := false;
      LastSpeedCounter := 100000000;
      StartMiningTimeStamp := UTCTime;
      SentThis := 0;
      GoodThis := 0;
      writeln('--------------------------------------------------------------------');
      Writeln(Format('Block: %d / Address: %s(%s...) / Cores: %d',[CurrentBlock, address, Copy(miningaddress,1,5),cpucount]));
      Writeln(Format('%s / Target: %s / %s / [%d]' ,[UpTime,Copy(TargetHash,1,10),SourceStr,TotalMinedBlocks]));
      for counter2 := 1 to CPUCount do
         begin
         MinerThread := TMinerThread.Create(true,counter2);
         MinerThread.FreeOnTerminate:=true;
         MinerThread.Start;
         sleep(1);
         end;
      OpenThreads := CPUCount;
      Repeat
         Sleep(10);
      until FinishProgram;
      end
   else if Uppercase(Parameter(command,0)) = 'HELP' then ShowHelp
   else if Uppercase(Parameter(command,0)) = 'SETTINGS' then ShowSettings
   else if Uppercase(Parameter(command,0)) = 'SOURCE' then
      begin
      if Uppercase(Parameter(command,1)) = 'ADD' then
         begin
         source := UpperCase(Parameter(Command,2))+' '+Source;
         savedata();
         Writeln('Source added : '+UpperCase(Parameter(Command,2)));
         end
      else if Uppercase(Parameter(command,1)) = 'CLEAR' then
         begin
         Source := 'Mainnet';
         savedata();
         Writeln('Source set to solo-mine');
         end
      else writeln('Use "Source add [Pool]" or "Source clear"');
      end
   else if Command <> '' then writeln('Invalid command');
UNTIL Uppercase(Command) = 'EXIT';
DoneCriticalSection(CS_MinerData);
DoneCriticalSection(CS_Solutions);
DoneCriticalSection(CS_Log);
DoneCriticalSection(CS_Interval);
END.// END PROGRAM


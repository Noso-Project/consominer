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
    private
      procedure UpdateScreen;
    protected
      procedure Execute; override;
    public
      Constructor Create(CreateSuspended : boolean);
    end;

  TMainThread = class(TThread)
    private
      procedure DoSomething;
      procedure UpdateBlockTime;
      procedure UpdateMainnetData;
    protected
      procedure Execute; override;
    public
      Constructor Create(CreateSuspended : boolean);
    end;

var
  command:string;
  MaxCPU : integer;
  // User options
  address : string = 'N2kFAtGWLb57Qz91sexZSAnYwA3T7Cy';
  cpucount : integer = 1;
  autostart : boolean = false;
  usegui    : boolean = false;
  TargetHash : string = '00000000000000000000000000000000';
  Consensus : TNodeData;
  Counter, Counter2 : integer;
  ArrMiners : Array of TMinerThread;
  MainThread : TMainThread;
  CPUspeed: extended;
  HashesToTest : integer = 5000;
  FirstRun : boolean = true;

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

procedure TMinerThread.UpdateScreen();
Begin
DoNothing();
End;

procedure TMainThread.DoSomething();
Begin

End;

procedure TMainThread.UpdateBlockTime();
Begin

End;

procedure TMainThread.UpdateMainnetData();
Begin

End;

procedure TMinerThread.Execute;
var
  BaseHash, ThisHash, ThisDiff : string;
Begin
While not FinishMiners do
   begin
   BaseHash := GetHashToMine;
   ThisHash := NosoHash(BaseHash+Address);
   ThisDiff := CheckHashDiff(TargetHash,ThisHash);
   if ThisDiff<TargetHash then writeln('Solution found');
   end;
End;

procedure TMainThread.Execute;
Begin
repeat
   if runminer then
      begin
      if (UTCTime) >= GetBlockEnd-15 then
         begin
         FinishMiners := true;

         end;
      if ( (UTCTime >= GetBlockEnd+10) and (LastSync+30<UTCTime) ) then
         begin
         Consensus := Getconsensus;;
         end;
      end;
   sleep(1000);
until FinishProgram;
End;

Procedure LoadData();
var
  datafile : textfile;
  linea : string;
Begin
Assignfile(datafile, 'data.txt');
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
   if uppercase(Parameter(linea,0)) = 'ADDRESS' then address := Parameter(linea,1);
   if uppercase(Parameter(linea,0)) = 'CPU' then cpucount := StrToIntDef(Parameter(linea,1),1);
   if uppercase(Parameter(linea,0)) = 'AUTOSTART' then autostart := StrToBoolDef(Parameter(linea,1),false);
   if uppercase(Parameter(linea,0)) = 'USEGUI' then usegui := StrToBoolDef(Parameter(linea,1),false);
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

Procedure ShowHelp();
Begin
Writeln('Available commands (Caps unsensitive)');
Writeln('help                   -> Shows this info');
Writeln('address {address}      -> The miner address');
Writeln('cpu {number}           -> Number of cores for minning');
Writeln('autostart {true/false} -> Start minning directly');
Writeln('minerid [1-8100]       -> Optional unique miner ID');
Writeln('test                   -> Speed test from 1 to Max CPUs');
Writeln('mine                   -> Start minning with current settings');
Writeln('exit                   -> Close the app');
Writeln('');
End;

{$R *.res}

begin
InitCriticalSection(CS_Counter);
InitCriticalSection(CS_ThisBlockEnd);
InitCriticalSection(CS_MinerData);
SetLEngth(ARRAY_Nodes,0);
MaxCPU:= {$IFDEF UNIX}GetSystemThreadCount{$ELSE}GetCPUCount{$ENDIF};
SetLength(ArrMiners,MaxCPU);
if not FileExists('data.txt') then savedata('N2kFAtGWLb57Qz91sexZSAnYwA3T7Cy',MaxCPU,false,false);
loaddata();
LoadSeedNodes;
writeln('Consominer Nosohash 1.0');
Writeln(GetOs+' --- '+MaxCPU.ToString+' CPUs --- '+Length(array_nodes).ToString+' Nodes');
writeln('Using '+address+' with '+CPUCount.ToString+' cores');
Write('Syncing...',#13);
Consensus:=GetConsensus;
Writeln(format('Block: %d / Age: %d secs / Hash: %s',[Consensus.block,UTCTime-Consensus.LBTimeEnd,Consensus.LBHash]));
LastSync := UTCTime;
SetBlockEnd(Consensus.LBTimeEnd+600);
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
      savedata(address,CPUCount,Autostart,usegui);
      writeln ('Minning address set to : '+address);
      end
   else if Uppercase(Parameter(command,0)) = 'CPU' then
      begin
      cpucount := StrToIntDef(parameter(command,1),CPUCount);
      savedata(address,CPUCount,Autostart,usegui);
      writeln ('Minning CPUs set to : '+CPUCount.ToString);
      end
   else if Uppercase(Parameter(command,0)) = 'TEST' then
      begin
      for counter :=1 to MaxCPU do
         begin
         write('Testing with '+counter.ToString+' CPUs: ');
         TestStart := GetTickCount64;
         FinishMiners := false;
         Testing:= true;
         Miner_Counter := 1000000000-(HashesToTest*counter);
         for counter2 := 1 to counter do
            begin
            ArrMiners[counter2-1] := TMinerThread.Create(true);
            ArrMiners[counter2-1].FreeOnTerminate:=true;
            ArrMiners[counter2-1].Start;
            end;
         ArrMiners[counter2-1].WaitFor;
         TestEnd := GetTickCount64;
         TestTime := (TestEnd-TestStart);
         CPUSpeed := HashesToTest/(testtime/1000);
         writeln(FormatFloat('0.00',CPUSpeed)+' -> '+FormatFloat('0.00',CPUSpeed*counter));
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
      savedata(address,CPUCount,Autostart,usegui);
      writeln ('Autostart set to : '+BoolToStr(autostart,true));
      end
   else if Uppercase(Parameter(command,0)) = 'USEGUI' then
      begin
      usegui := StrToBoolDef(parameter(command,1),usegui);
      savedata(address,CPUCount,Autostart,usegui);
      writeln ('UseGUI set to : '+BoolToStr(usegui,true));
      end
   else if Uppercase(Parameter(command,0)) = 'MINE' then
      begin
      RunMiner := true;
      writeln('Minning with '+CPUcount.ToString+' CPUs');
      writeln('Press CTRL+C to finish');
      FinishMiners := false;
      Miner_Counter := 1000000000;
      for counter2 := 1 to CPUCount do
         begin
         ArrMiners[counter2-1] := TMinerThread.Create(true);
         ArrMiners[counter2-1].FreeOnTerminate:=true;
         ArrMiners[counter2-1].Start;
         end;
      Repeat
      until RunMiner = false;
      end
   else if Uppercase(Parameter(command,0)) = 'HELP' then
      begin
      ShowHelp;
      end
   else
      begin
      donothing; // invalid command
      end;

UNTIL Uppercase(command) = 'EXIT';
DoneCriticalSection(CS_Counter);
DoneCriticalSection(CS_ThisBlockEnd);
DoneCriticalSection(CS_MinerData);
end.// end program


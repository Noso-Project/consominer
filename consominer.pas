program consominer;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}{$IFDEF UseCThreads}
  cthreads,
  {$ENDIF}{$ENDIF}
  Classes, sysutils, nosocoreunit, crt, strutils, windows
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

var
  command:string;
  MaxCPU : integer;
  address : string;
  cpucount : integer;
  autostart : boolean;
  TargetHash : string = '00000000000000000000000000000000';
  Consensus : TNodeData;
  Counter, Counter2 : integer;
  ArrMiners : Array of TMinerThread;
  CPUspeed, TotalSpeed: extended;

constructor TMinerThread.Create(CreateSuspended : boolean);
Begin
inherited Create(CreateSuspended);
FreeOnTerminate := True;
End;

procedure TMinerThread.UpdateScreen();
Begin
DoNothing();
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
   if ThisDiff<TargetHash then Synchronize(@UpdateScreen);
   end;
End;

Procedure PrintXY(x,y,long:integer;texto:string;colour:integer);
Begin
textcolor(colour);
texto := AddCharR(#32,texto,long);
gotoxy(x,y);
Write(Texto);
End;

Procedure DrawGUI();
Begin
ClrScr;
Textcolor(LightGray);
Writeln(#201+crtline+#187);
writeln(#186+'                                                                             '+#186);
Writeln(#204+CRTLine+#185);
writeln(#186+' Detected OS     :            Max CPUs :       Nodes :                       '+#186);
Writeln(#204+CRTLine+#185);
writeln(#186+' Minning address :                                       CPUs :              '+#186);
Writeln(#204+CRTLine+#185);
writeln(#186+' Block :           Age :        Hash :                                       '+#186);
writeln(#186+' Best hash :                                                                 '+#186);
writeln(#186+'                                                                             '+#186);
writeln(#186+'                                                                             '+#186);
Writeln(#204+CRTLine+#185);
writeln(#186+'                                                                             '+#186);
Writeln(#200+CRTLine+#188);
//Writeln('Console output codepage: ', GetTextCodePage(Output));
PrintXY(30,2,40,'Consominer Nosohash 1.0',yellow);
PrintXY(21,4,10,GetOs,yellow);
PrintXY(43,4,5,MaxCPU.ToString,yellow);
PrintXY(58,4,2,Length(array_nodes).ToString,yellow);
PrintXY(21,6,35,address,green);
PrintXY(66,6,2,CPUCount.ToString,green);
End;

procedure FillMainnetData();
Begin
PrintXY(11,8,7,(Consensus.block).ToString,LightCyan);
PrintXY(27,8,5,IntToStr(UTCTime-Consensus.LBTimeEnd),LightCyan);
PrintXY(41,8,32,Consensus.LBHash,LightCyan);
PrintXY(15,9,32,Consensus.NMSDiff,LightCyan);
End;

Procedure LoadData();
var
  datafile : textfile;
  linea : string;
Begin
Assignfile(datafile, 'data.txt');
reset(datafile);
readln(datafile,linea);
address := Parameter(linea,1);
readln(datafile,linea);
cpucount := StrToIntDef(Parameter(linea,1),1);
readln(datafile,linea);
autostart := StrToBool(Parameter(linea,1));
CloseFile(datafile);
End;

{$R *.res}

begin
SetConsoleOutputCP(DefaultSystemCodePage);
SetTextCodePage(Output, DefaultSystemCodePage);
InitCriticalSection(CS_Counter);
SetLEngth(ARRAY_Nodes,0);
MaxCPU:= {$IFDEF UNIX}GetSystemThreadCount{$ELSE}GetCPUCount{$ENDIF};
SetLength(ArrMiners,MaxCPU);
if not FileExists('data.txt') then savedata('devteam_donations',MaxCPU,false);
loaddata();
LoadSeedNodes;
CRTLine := AddCharR(#205,CRTLine,77);
DrawGUI;
PrintXY(65,2,10,' Syncing... ',blink+green);
Consensus:=GetConsensus;
PrintXY(65,2,10,'            ',black);
FillMainnetData;


REPEAT
   PrintXY(3,13,75,'>>',LightGray);
   gotoxy(6,13);
   Textcolor(white);
   readln(command);
   if Uppercase(Parameter(command,0)) = 'ADDRESS' then
      begin
      address := parameter(command,1);
      savedata(address,CPUCount,Autostart);
      PrintXY(21,6,40,address,green);
      end
   else if Uppercase(Parameter(command,0)) = 'CPU' then
      begin
      cpucount := StrToIntDef(parameter(command,1),CPUCount);
      savedata(address,CPUCount,Autostart);
      PrintXY(21,7,40,CPUCount.ToString,green);
      end
   else if Uppercase(Parameter(command,0)) = 'TEST' then
      begin
      clrscr();
      for counter :=1 to MaxCPU do
         begin
         write('Testing with '+counter.ToString+' CPUs: ');
         TestStart := GetTickCount64;
         FinishMiners := false;
         Testing:= true;
         Miner_Counter := 1000000000-(25000*counter);
         for counter2 := 1 to counter do
            begin
            ArrMiners[counter2-1] := TMinerThread.Create(true);
            ArrMiners[counter2-1].FreeOnTerminate:=true;
            ArrMiners[counter2-1].Start;
            end;
         ArrMiners[counter2-1].WaitFor;
         TestEnd := GetTickCount64;
         TestTime := (TestEnd-TestStart);
         CPUSpeed := 25000/(testtime/1000);
         writeln(FormatFloat('0.00',CPUSpeed)+' -> '+FormatFloat('0.00',CPUSpeed*counter));
         end;
      Testing := false;
      Writeln('Press any key to continue...');
      cursoroff;
      Waitingkey := Readkey;
      cursoron;
      DrawGui();
      FillMainnetData;
      end
   else if Uppercase(Parameter(command,0)) = 'EXIT' then
      begin
      DoNothing;
      end
   else
      begin
      Sound(100);
      Delay(100);
      NoSound;
      end;

UNTIL Uppercase(command) = 'EXIT';
DoneCriticalSection(CS_Counter);
end.// end program


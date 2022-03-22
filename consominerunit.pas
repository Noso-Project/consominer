unit ConsominerUnit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

var
  OpenMinerThreads : Integer = 0;                   {CS Protected}
    CS_MinerThreads  : TRTLCriticalSection;

Procedure SetOMT(value:integer);
Procedure DecreaseOMT();
Function GetOMTValue():Integer;


IMPLEMENTATION

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
LeaveCriticalSection(CS_MinerThreads);
End;

Function GetOMTValue():Integer;
Begin
EnterCriticalSection(CS_MinerThreads);
Result := OpenMinerThreads;
LeaveCriticalSection(CS_MinerThreads);
End;

INITIALIZATION
InitCriticalSection(CS_MinerThreads);

FINALIZATION
LEaveCriticalSection(CS_MinerThreads);

END. {End unit}


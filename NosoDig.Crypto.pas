unit NosoDig.Crypto;

{$ifdef FPC}
  {$mode DELPHI}{$H+}
{$endif}
{$ifopt D+}
  {$define DEBUG}
{$endif}

interface

uses
  Classes,
  SysUtils;

const
  MAX_DIFF = 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF';

type
  THash32      = array[1.. 32] of Char; {  256 bits }
  THash128     = array[1..128] of Char;
  TByteHash128 = array[1..128] of Byte; { 1024 bits }


function NosoHash(Source: String): THash32;
function GetHashDiff(const HashA, HashB: THash32): THash32;

{ Fast lookup functions }
function FastBinToHex(const B: Byte): Char;
function FastHexToBin(const C: Char): Byte;

implementation

uses
  MD5;

var
  _CleanAsciiLookup: array[1..512] of Byte;
  _HexToBinLookup  : array[48..70] of Byte;


function Mutate(sHash: THash128; const nSteps: Smallint=128): TByteHash128;{$ifndef DEBUG}inline;{$endif}
var
  LHash: TByteHash128 absolute sHash;
  bFirst: Byte;
  I, N, HashLen: Integer;
begin
  Result[1] := 0;
  HashLen := Length(LHash);
  for N:=1 to nSteps do
  begin
    bFirst := LHash[1];
    for I:=1 to HashLen-1 do
      LHash[I] := _CleanAsciiLookup[LHash[  I] + LHash[I+1]];
    LHash[128] := _CleanAsciiLookup[LHash[128] + bFirst];
  end;
  Move(LHash, Result, SizeOf(TByteHash128));
end;

function NosoHash(Source: String): THash32;
const
  FILLER = '%)+/5;=CGIOSYaegk';
var
  N, I, iSum: SmallInt;
  LHash: TByteHash128;
  RHash: THash32;
begin
  Result := '';
  RHash  := '';

  if Length(Source) > 63 then
    Source := '';
  for N := 1 to Length(Source) do
    if (Ord(Source[N]) < 33) or (Ord(Source[N]) > 126) then
    begin
      Source := '';
      Break;
    end;

  { fill Source with FILLER string }
  repeat
    Source := Source + FILLER;
  until Length(Source) >= 128;
  SetLength(Source, 128);

  LHash := Mutate(Source);

  for N := 0 to 31 do
  begin
    I := N*4;
    iSum := LHash[I+1] + LHash[I+2] + LHash[I+3] + LHash[I+4];
    RHash[N+1] := FastBinToHex(_CleanAsciiLookup[iSum] mod 16);
  end;
  Result := MD5Print(MDBuffer(RHash, SizeOf(THash32), MD_VERSION_5)).ToUpper;
end;

function GetHashDiff(const HashA, HashB: THash32): THash32;
var
  I: Integer;
begin
  Result := MAX_DIFF;
  for I := 1 to 32 do
    Result[I] := HexStr(Abs(FastHexToBin(HashB[I])-FastHexToBin(HashA[I])), 1)[1];
end;

function FastBinToHex(const B: Byte): Char;{$ifndef DEBUG}inline;{$endif}
const
  HexLookup: array[0..15] of Char = ('0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F');
begin
  if (B > 15) then
    Exit(#0);
  Result := HexLookup[B]
end;

function FastHexToBin(const C: Char): Byte;{$ifndef DEBUG}inline;{$endif}
begin
  Result := _HexToBinLookup[Ord(C)];
end;

procedure FillLookupTables;{$ifndef DEBUG}inline;{$endif}
var
  I, N: Word;
  c: Char;
begin
  FillChar(_HexToBinLookup, Length(_HexToBinLookup), 0);
  for c:='0' to '9' do
    _HexToBinLookup[Ord(c)] := Ord(c)-48;
  for c:='A' to 'F' do
    _HexToBinLookup[Ord(c)] := Ord(c)-55;

  { ASCII lookup table }
  FillChar(_CleanAsciiLookup, Length(_CleanAsciiLookup), 0);
  for I:=Low(_CleanAsciiLookup) to High(_CleanAsciiLookup) do
  begin
    N := I;
    while N > 126 do Dec(N, 95);
    _CleanAsciiLookup[I] := N;
  end;
end;

initialization
  FillLookupTables;

end.


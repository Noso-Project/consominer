unit NosoDig.Crypto68b;

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

type
  THash32 = array[0..31] of Char; {  256 bits }

function NosoHash68b(S: String): THash32;
function GetHashDiff68b(const HashA, HashB: THash32): THash32;

implementation

uses
  MD5;

type
  PByteHash128 = ^TByteHash128;
  TByteHash128 = packed array[0..127] of Byte; { 1024 bits }

  PAsciiLookup = ^TAsciiLookup;
  TAsciiLookup = packed array[0..504] of Byte;

const
  MAX_DIFF = 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF';

var
  AsciiLookupTable: TAsciiLookup;


function BinToHexFast(const B: Byte): Char;{$ifndef DEBUG}inline;{$endif}
const
  bin2hex_lookup: array[0..15] of Char =
    ('0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F');
begin
  if (B > 15) then
    Exit(#0);
  Result := bin2hex_lookup[B]
end;

function HexToBinFast(const C: Char): Byte;{$ifndef DEBUG}inline;{$endif}
const
  hex2bin_lookup: array['0'..'F'] of Byte =
    (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 0, 0, 0, 0, 0, 0, 10, 11, 12, 13, 14, 15);
begin
  Assert( ((C>='0') and (C<='9')) or ((C>='A') and (C<='F')));
  Result := hex2bin_lookup[C];
end;

function NosoHash68b(S: String): THash32;
var
  i, n, LFirst: Byte;
  p, tab: PByte;
const
  NOSOHASH_FILLER = '%)+/5;=CGIOSYaegk';
begin
  Result := '';
  tab := @AsciiLookupTable;

  if Length(S) > 63 then
    SetLength(S, 0);

  for i := 1 to Length(S) do
    if (Ord(S[i]) < 33) or (Ord(S[i]) > 126) then
    begin
      SetLength(S, 0);
      Break;
    end;

  repeat
    S := S + NOSOHASH_FILLER;
  until Length(S) >= 128;

{+20us}
  for n:=1 to 128 do
  begin
    p := Pointer(S);
    LFirst := p^;
    for i:=0 to 126 do
    begin
      p^ := PByte(tab + (p^ + PByte(p+1)^))^;
      Inc(p);
    end;
    p^ := PByte(tab + (p^ + LFirst))^;
  end;
{+2us}
  p := Pointer(S);
  for i:=0 to 31 do
  begin
    Result[i] := BinToHexFast(PByte(tab + (p^ + PByte(p+1)^ + PByte(p+2)^ + PByte(p+3)^))^ mod 16);
    Inc(p, 4);
  end;
{+10us}
  Result := MD5Print(MDBuffer(Result, SizeOf(THash32), MD_VERSION_5)).ToUpper;
end;

function GetHashDiff68b(const HashA, HashB: THash32): THash32;
var
  i: Integer;
begin
  Result := MAX_DIFF;
  for i := 0 to 31 do
    Result[i] := HexStr(Abs(HexToBinFast(HashB[i]) - HexToBinFast(HashA[i])), 1)[1];
end;

procedure FillLookupTables;
var
  i, n: Word;
begin
  for i:=Low(AsciiLookupTable) to High(AsciiLookupTable) do
  begin
    n := i;
    while n > 126 do Dec(n, 95);
    AsciiLookupTable[i] := n;
  end;
end;

initialization
  FillLookupTables;
end.
end.

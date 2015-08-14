unit DIBImageReader;

{$mode objfpc}

interface

uses
  Classes, SysUtils, FPimage,BMPcomn;

type

  PBitmapCoreHeader = ^TBitmapCoreHeader;
  tagBITMAPCOREHEADER = record
    bcSize: DWORD;
    bcWidth: Word;
    bcHeight: Word;
    bcPlanes: Word;
    bcBitCount: Word;
  end;
  TBitmapCoreHeader = tagBITMAPCOREHEADER;
  BITMAPCOREHEADER = tagBITMAPCOREHEADER;


  PBitmapInfoHeader = ^TBitmapInfoHeader;
  tagBITMAPINFOHEADER = record
    biSize : DWORD;
    biWidth : Longint;
    biHeight : Longint;
    biPlanes : WORD;
    biBitCount : WORD;
    biCompression : DWORD;
    biSizeImage : DWORD;
    biXPelsPerMeter : Longint;
    biYPelsPerMeter : Longint;
    biClrUsed : DWORD;
    biClrImportant : DWORD;
  end;
  TBitmapInfoHeader = tagBITMAPINFOHEADER;
  BITMAPINFOHEADER = tagBITMAPINFOHEADER;


{ TLazReaderDIB }
{ This is an imroved FPImage reader for dib images. }

TLazReaderMaskMode = (
  lrmmNone,  // no mask is generated
  lrmmAuto,  // a mask is generated based on the first pixel read (*)
  lrmmColor  // a mask is generated based on the given color (*)
);
// (*) Note: when reading images with an alpha channel and the alpha channel
//           has no influence on the mask (unless the maskcolor is transparent)

TLazReaderDIBEncoding = (
  lrdeRGB,
  lrdeRLE,
  lrdeBitfield,
  lrdeJpeg,     // for completion, don't know if they exist
  lrdePng,      // for completion, don't know if they exist
  lrdeHuffman   // for completion, don't know if they exist
);

TLazReaderDIBInfo = record
  Width: Cardinal;
  Height: Cardinal;
  BitCount: Byte;
  Encoding: TLazReaderDIBEncoding;
  PaletteCount: Word;
  UpsideDown: Boolean;
  PixelMasks: packed record
    R, G, B, A: LongWord;
  end;
  MaskShift: record
    R, G, B, A: Byte;
  end;
  MaskSize: record
    R, G, B, A: Byte;
  end;
end;

{ TLazReaderDIB }

TLazReaderDIB = class (TFPCustomImageReader)
private
  FImage: TFPCustomImage;

  FMaskMode: TLazReaderMaskMode;
  FMaskColor: TFPColor; // color which should be interpreted as masked
  FMaskIndex: Integer;  // for palette based images, index of the color which should be interpreted as masked

  FReadSize: Integer;          // Size (in bytes) of 1 scanline.
  FDIBinfo: TLazReaderDIBInfo; // Info about the bitmap as read from the stream
  FPalette: array of TFPColor; // Buffer with Palette entries.
  FLineBuf: PByte;             // Buffer for 1 scanline. Can be Byte, Word, TColorRGB or TColorRGBA
  FUpdateDescription: Boolean; // If set, update rawimagedescription
  FContinue: Boolean;          // for progress support
  FIgnoreAlpha: Boolean;       // if alpha-channel is declared but does not exists (all values = 0)

  function BitfieldsToFPColor(const AColor: Cardinal): TFPcolor;
  function RGBToFPColor(const AColor: TColorRGBA): TFPcolor;
  function RGBToFPColor(const AColor: TColorRGB): TFPcolor;
  function RGBToFPColor(const AColor: Word): TFPcolor;

public
  function  GetUpdateDescription: Boolean;
  procedure SetUpdateDescription(AValue: Boolean);
  function QueryInterface(constref iid: TGuid; out obj): LongInt; {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
  function _AddRef: LongInt; {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
  function _Release: LongInt; {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
protected
  procedure InitLineBuf;
  procedure FreeLineBuf;


  procedure ReadScanLine(Row: Integer); virtual;
  procedure WriteScanLine(Row: Cardinal); virtual;
  // required by TFPCustomImageReader
  procedure InternalRead(Stream: TStream; Img: TFPCustomImage); override;
  procedure InternalReadHead; virtual;
  procedure InternalReadBody; virtual;
  function  InternalCheck(Stream: TStream) : boolean; override;

  property ReadSize: Integer read FReadSize;
  property LineBuf: PByte read FLineBuf;
  property Info: TLazReaderDIBInfo read FDIBInfo;
public
  constructor Create; override;
  destructor Destroy; override;
  property MaskColor: TFPColor read FMaskColor write FMaskColor;
  property MaskMode: TLazReaderMaskMode read FMaskMode write FMaskMode;
  property UpdateDescription: Boolean read GetUpdateDescription write SetUpdateDescription;
end;

implementation

type
  PFPColorBytes = ^TFPColorBytes;
  TFPColorBytes = record
    {$ifdef ENDIAN_LITTLE}
    Rl, Rh, Gl, Gh, Bl, Bh, Al, Ah: Byte;
    {$else}
    Rh, Rl, Gh, Gl, Bh, Bl, Ah, Al: Byte;
    {$endif}
  end;

  PFourBytes = ^TFourBytes;
  TFourBytes = record
    B0, B1, B2, B3: Byte;
  end;


{ TLazReaderDIB }

procedure TLazReaderDIB.InitLineBuf;
begin
  FreeLineBuf;

  if Info.BitCount < 8
  then FReadSize := ((Info.BitCount * Info.Width + 31) shr 5) shl 2
  else FReadSize := (((Info.BitCount shr 3) * Info.Width + 3) shr 2) shl 2;

  // allocate 3 bytes more so we can always use a cardinal to read (in case of bitfields)
  GetMem(FLineBuf, FReadSize+3);
end;

procedure TLazReaderDIB.FreeLineBuf;
begin
  FreeMem(FLineBuf);
  FLineBuf := nil;
end;

function TLazReaderDIB.GetUpdateDescription: Boolean;
begin
  Result := FUpdateDescription;
end;

procedure TLazReaderDIB.ReadScanLine(Row: Integer);
  procedure DoRLE4;
  var
    Head: array[0..1] of Byte;
    Value, NibbleCount, ByteCount: Byte;
    WriteNibble: Boolean;       // Set when only lower nibble needs to be written
    BufPtr, DstPtr: PByte;
    Buf: array[0..127] of Byte; // temp buffer to read nibbles
  begin
    DstPtr := @LineBuf[0];
    WriteNibble := False;
    while True do
    begin
      TheStream.Read(Head[0], 2);
      NibbleCount := Head[0];

      if NibbleCount > 0 then
      begin
        if WriteNibble
        then begin
          // low nibble needs to be written
          // swap pixels so that they are in order after this nibble
          Value := (Head[1] shl 4) or (Head[1] shr 4);
          DstPtr^ := (DstPtr^ and $F0) or (Value and $0F);
          Inc(DstPtr);
          // we have written one
          Dec(NibbleCount);
        end
        else begin
          Value := Head[1];
        end;
        ByteCount := (NibbleCount + 1) div 2;
        FillChar(DstPtr^, ByteCount , Value);
        // if we have written an odd number of nibbles we still have to write one
        WriteNibble := NibbleCount and 1 = 1;
        Inc(DstPtr, ByteCount);
        // correct DstPtr if we still need to write a nibble
        if WriteNibble then Dec(DstPtr);
      end
      else begin
        NibbleCount := Head[1];
        case NibbleCount of
          0, 1: break;       // End of scanline or end of bitmap
          2: raise FPImageException.Create('RLE code #2 is not supported');
        else
          ByteCount := (NibbleCount + 1) div 2;

          if WriteNibble
          then begin
            // we cannot read directly into destination, so use temp buf
            TheStream.Read(Buf[0], ByteCount);
            BufPtr := @Buf[0];
            repeat
              DstPtr^ := (DstPtr^ and $F0) or (BufPtr^ shr 4);
              Inc(DstPtr);
              Dec(NibbleCount);
              if NibbleCount = 0
              then begin
                // if we have written both nibbles
                WriteNibble := False;
                Break;
              end;
              DstPtr^ := (BufPtr^ shl 4);
              Inc(BufPtr);
              Dec(NibbleCount);
            until NibbleCount = 0;
          end
          else begin
            TheStream.Read(DstPtr^, ByteCount);
            // if we have written an odd number of nibbles we still have to write one
            WriteNibble := NibbleCount and 1 = 1;
            Inc(DstPtr, ByteCount);
            // correct DstPtr if we still need to write a nibble
            if WriteNibble then Dec(DstPtr);
          end;

          // keep stream at word boundary
          if ByteCount and 1 = 1
          then TheStream.Seek(1, soCurrent);
        end;
      end;

    end
  end;

  procedure DoRLE8;
  var
    Head: array[0..1] of Byte;
    Value, Count: Byte;
    DstPtr: PByte;
  begin
    DstPtr := @LineBuf[0];
    while True do
    begin
      TheStream.Read(Head[0], 2);
      Count := Head[0];
      if Count > 0
      then begin
        Value := Head[1];
        FillChar(DstPtr^, Count, Value);
      end
      else begin
        Count := Head[1];
        case Count of
          0, 1: break;       // End of scanline or end of bitmap
          2: raise FPImageException.Create('RLE code #2 is not supported');
        else
          TheStream.Read(DstPtr^, Count);
          // keep stream at word boundary
          if Count and 1 = 1
          then TheStream.Seek(1, soCurrent);
        end;
      end;

      Inc(DstPtr, Count);
    end
  end;
begin
  // Add here support for compressed lines. The 'readsize' is the same in the end.

  // MWE: Note: when doing so, keep in mind that the bufer is expected to be in Little Endian.
  // for better performance, the conversion is done when writeing the buffer.

  if Info.Encoding = lrdeRLE
  then begin
    case Info.BitCount of
      4: DoRLE4;
      8: DoRLE8;
     //24: DoRLE24;
    end;
  end
  else begin
    TheStream.Read(LineBuf[0], ReadSize);
  end;
end;

function TLazReaderDIB.BitfieldsToFPColor(const AColor: Cardinal): TFPcolor;
var
  V: Word;
begin
  //--- red ---
  V := ((AColor and Info.PixelMasks.R) shl (32 - Info.MaskShift.R - Info.MaskSize.R)) shr 16;
  Result.Red := V;
  repeat
    V := V shr Info.MaskSize.R;
    Result.Red := Result.Red or V;
  until V = 0;

  //--- green ---
  V := ((AColor and Info.PixelMasks.G) shl (32 - Info.MaskShift.G - Info.MaskSize.G)) shr 16;
  Result.Green := V;
  repeat
    V := V shr Info.MaskSize.G;
    Result.Green := Result.Green or V;
  until V = 0;

  //--- blue ---
  V := ((AColor and Info.PixelMasks.B) shl (32 - Info.MaskShift.B - Info.MaskSize.B)) shr 16;
  Result.Blue := V;
  repeat
    V := V shr Info.MaskSize.B;
    Result.Blue := Result.Blue or V;
  until V = 0;

  //--- alpha ---
  if Info.MaskSize.A = 0
  then begin
    Result.Alpha := AlphaOpaque;
  end
  else begin
    V := ((AColor and Info.PixelMasks.A) shl (32 - Info.MaskShift.A - Info.MaskSize.A)) shr 16;
    Result.Alpha := V;
    repeat
      V := V shr Info.MaskSize.A;
      Result.Alpha := Result.Alpha or V;
    until V = 0;
  end;
end;

function TLazReaderDIB.RGBToFPColor(const AColor: TColorRGB): TFPcolor;
var
  RBytes: TFPColorBytes absolute Result;
begin
  RBytes.Bh := AColor.B;
  RBytes.Bl := AColor.B;
  RBytes.Gh := AColor.G;
  RBytes.Gl := AColor.G;
  RBytes.Rh := AColor.R;
  RBytes.Rl := AColor.R;
  Result.Alpha := AlphaOpaque;
end;

function TLazReaderDIB.RGBToFPColor(const AColor: TColorRGBA): TFPcolor;
var
  RBytes: TFPColorBytes absolute Result;
begin
  RBytes.Bh := AColor.B;
  RBytes.Bl := AColor.B;
  RBytes.Gh := AColor.G;
  RBytes.Gl := AColor.G;
  RBytes.Rh := AColor.R;
  RBytes.Rl := AColor.R;
  if Info.MaskSize.A = 0
  then Result.Alpha := AlphaOpaque
  else begin
    RBytes.Ah := AColor.A;
    RBytes.Al := AColor.A;
  end;
end;

function TLazReaderDIB.RGBToFPColor(const AColor: Word): TFPcolor;
var
  V1, V2: Cardinal;
begin
  // 5 bit for red  -> 16 bit for TFPColor
  V1 := (AColor shl 1) and $F800;     // 15..11
  V2 := V1;
  V1 := V1 shr 5;                  // 10..6
  V2 := V2 or V1;
  V1 := V1 shr 5;                  // 5..1
  V2 := V2 or V1;
  V1 := V1 shr 5;                  // 0
  Result.Red := Word(V2 or V1);
  // 5 bit for red  -> 16 bit for TFPColor
  V1 := (AColor shl 6) and $F800;     // 15..11
  V2 := V1;
  V1 := V1 shr 5;                  // 10..6
  V2 := V2 or V1;
  V1 := V1 shr 5;                  // 5..1
  V2 := V2 or V1;
  V1 := V1 shr 5;                  // 0
  Result.Green := Word(V2 or V1);
  // 5 bit for blue -> 16 bit for TFPColor
  V1 := (AColor shl 11) and $F800;    // 15..11
  V2 := V1;
  V1 := V1 shr 5;
  V2 := V2 or V1;                  // 10..6
  V1 := V1 shr 5;
  V2 := V2 or V1;                  // 5..1
  V1 := V1 shr 5;
  Result.Blue := Word(V2 or V1);   // 0
  // opaque, no mask
  Result.Alpha:=alphaOpaque;
end;

procedure TLazReaderDIB.SetUpdateDescription(AValue: Boolean);
begin
  FUpdateDescription := AValue;
end;

procedure TLazReaderDIB.WriteScanLine(Row: Cardinal);
// using cardinals generates compacter code
var
  Column: Cardinal;
  Color: TFPColor;
  Index: Byte;
begin
  if FMaskMode = lrmmNone
  then begin
    case Info.BitCount of
     1 :
       for Column := 0 to TheImage.Width - 1 do
         TheImage.colors[Column,Row] := FPalette[Ord(LineBuf[Column div 8] and ($80 shr (Column and 7)) <> 0)];
     4 :
       for Column := 0 to TheImage.Width - 1 do
         TheImage.colors[Column,Row] := FPalette[(LineBuf[Column div 2] shr (((not Column) and 1)*4)) and $0f];
     8 :
       for Column := 0 to TheImage.Width - 1 do
         TheImage.colors[Column,Row] := FPalette[LineBuf[Column]];
    else
      if Info.Encoding = lrdeBitfield
      then begin
        // always cast to cardinal without conversion
        // this way the value will have the same order as the bitfields
        case Info.BitCount of
          16:
            for Column := 0 to TheImage.Width - 1 do
              TheImage.colors[Column,Row] := BitfieldsToFPColor(PCardinal(@PWord(LineBuf)[Column])^);
          24:
            for Column := 0 to TheImage.Width - 1 do
              TheImage.colors[Column,Row] := BitfieldsToFPColor(PCardinal(@PColorRGB(LineBuf)[Column])^);
          32:
            for Column := 0 to TheImage.Width - 1 do
            begin
              Color := BitfieldsToFPColor(PCardinal(@PColorRGBA(LineBuf)[Column])^);
              TheImage.colors[Column,Row] := Color;
              FIgnoreAlpha := FIgnoreAlpha and (Color.alpha = alphaTransparent);
            end;
        end;
      end
      else begin
        case Info.BitCount of
          16:
            for Column := 0 to TheImage.Width - 1 do
              TheImage.colors[Column,Row] := RGBToFPColor({$ifdef FPC_BIG_ENDIAN}LeToN{$endif}(PWord(LineBuf)[Column]));
          24:
            for Column := 0 to TheImage.Width - 1 do
              TheImage.colors[Column,Row] := RGBToFPColor(PColorRGB(LineBuf)[Column]);
          32:
            for Column := 0 to TheImage.Width - 1 do
            begin
              Color := RGBToFPColor(PColorRGBA(LineBuf)[Column]);
              TheImage.colors[Column,Row] := Color;
              FIgnoreAlpha := FIgnoreAlpha and (Color.alpha = alphaTransparent);
            end;
        end;
      end;
    end;
  end
  else begin
    case Info.BitCount of
     1 :
       for Column := 0 to TheImage.Width - 1 do
       begin
         Index := Ord(LineBuf[Column div 8] and ($80 shr (Column and 7)) <> 0);
         FImage.colors[Column,Row] := FPalette[Index];
         //FImage.Masked[Column,Row] := Index = FMaskIndex;
       end;
     4 :
       for Column := 0 to TheImage.Width - 1 do
       begin
         Index := (LineBuf[Column div 2] shr (((not Column) and 1)*4)) and $0f;
         FImage.colors[Column,Row] := FPalette[Index];
         //FImage.Masked[Column,Row] := Index = FMaskIndex;
       end;
     8 :
       for Column := 0 to TheImage.Width - 1 do
       begin
         Index := LineBuf[Column];
         FImage.colors[Column,Row] := FPalette[Index];
         //FImage.Masked[Column,Row] := Index = FMaskIndex;
       end;
    else
      if Info.Encoding = lrdeBitfield
      then begin
        // always cast to cardinal without conversion
        // this way the value will have the same order as the bitfields
        case Info.BitCount of
         16:
           for Column := 0 to TheImage.Width - 1 do
           begin
             Color := BitfieldsToFPColor(PCardinal(@PWord(LineBuf)[Column])^);
             FImage.colors[Column,Row] := Color;
             //FImage.Masked[Column,Row] := Color = FMaskColor;
           end;
         24:
           for Column := 0 to TheImage.Width - 1 do
           begin
             Color := BitfieldsToFPColor(PCardinal(@PColorRGB(LineBuf)[Column])^);
             FImage.colors[Column,Row] := Color;
             //FImage.Masked[Column,Row] := Color = FMaskColor;
           end;
         32:
           for Column := 0 to TheImage.Width - 1 do
           begin
             Color := BitfieldsToFPColor(PCardinal(@PColorRGBA(LineBuf)[Column])^);
             FImage.colors[Column,Row] := Color;
             //FImage.Masked[Column,Row] := Color = FMaskColor;
             FIgnoreAlpha := FIgnoreAlpha and (Color.alpha = alphaTransparent);
           end;
        end;
      end
      else begin
        case Info.BitCount of
         16:
           for Column := 0 to TheImage.Width - 1 do
           begin
             Color := RGBToFPColor({$ifdef FPC_BIG_ENDIAN}LeToN{$endif}(PWord(LineBuf)[Column]));
             FImage.colors[Column,Row] := Color;
             //FImage.Masked[Column,Row] := Color = FMaskColor;
           end;
         24:
           for Column := 0 to TheImage.Width - 1 do
           begin
             Color := RGBToFPColor(PColorRGB(LineBuf)[Column]);
             FImage.colors[Column,Row] := Color;
             //FImage.Masked[Column,Row] := Color = FMaskColor;
           end;
         32:
           for Column := 0 to TheImage.Width - 1 do
           begin
             Color := RGBToFPColor(PColorRGBA(LineBuf)[Column]);
             FImage.colors[Column,Row] := Color;
             //FImage.Masked[Column,Row] := Color = FMaskColor;
             FIgnoreAlpha := FIgnoreAlpha and (Color.alpha = alphaTransparent);
           end;
        end;
      end;
    end;
  end;
end;

function TLazReaderDIB._AddRef: LongInt; {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
begin
  Result := -1;
end;

function TLazReaderDIB._Release: LongInt; {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
begin
  Result := -1;
end;

procedure TLazReaderDIB.InternalRead(Stream: TStream; Img: TFPCustomImage);
var
  //Desc: TRawImageDescription;
  Depth: Byte;
begin
  FContinue := True;
  Progress(psStarting, 0, False, Rect(0,0,0,0), '', FContinue);
  FImage := TheImage;// as TLazIntfImage;
  FIgnoreAlpha := True;
  InternalReadHead;

  if FUpdateDescription
  then begin
    if (Info.BitCount = 32) and (Info.MaskSize.A = 0)
    then Depth := 24
    else Depth := Info.BitCount;
    //DefaultReaderDescription(Info.Width, Info.Height, Depth, Desc);
    //FImage.DataDescription := Desc;
  end;

  InternalReadBody;

  // if there is no alpha in real (all alpha values = 0) then update the description
  if FUpdateDescription and FIgnoreAlpha and (Depth = 32) then
  begin
    //Desc.AlphaPrec:=0;
    //FImage.SetDataDescriptionKeepData(Desc);
  end;

  Progress(psEnding, 100, false, Rect(0,0,0,0), '', FContinue);
end;

procedure TLazReaderDIB.InternalReadHead;
const
  SUnknownCompression = 'Bitmap with unknown compression (%d)';
  SUnsupportedCompression = 'Bitmap with unsupported compression (%s)';
  SWrongCombination = 'Bitmap with wrong combination of bit count (%d) and compression (%s)';
  SUnsupportedPixelMask = 'Bitmap with non-standard pixel masks not supported';

  SEncoding: array[TLazReaderDIBEncoding] of string = (
    'RGB',
    'RLE',
    'Bitfield',
    'Jpeg',
    'Png',
    'Huffman'
  );

  function ValidCompression: Boolean;
  begin
    case Info.BitCount of
      1:   Result := FDibInfo.Encoding in [lrdeRGB, lrdeHuffman];
      4,8: Result := FDibInfo.Encoding in [lrdeRGB, lrdeRLE];
      16:  Result := FDibInfo.Encoding in [lrdeRGB, lrdeBitfield];
      24:  Result := FDibInfo.Encoding in [lrdeRGB, lrdeBitfield, lrdeRLE];
      32:  Result := FDibInfo.Encoding in [lrdeRGB, lrdeBitfield];
    else
      raise FPImageException.CreateFmt('Wrong bitmap bit count: %d', [Info.BitCount]);
    end;
  end;

  procedure GetMaskShiftSize(AMask: LongWord; var AShift, ASize: Byte);
  begin
    AShift := 0;
    repeat
      if (AMask and 1) <> 0 then Break;
      AMask := AMask shr 1;
      Inc(AShift);
    until AShift >= 32;

    ASize := 0;
    repeat
      if (AMask and 1) = 0 then Break;
      AMask := AMask shr 1;
      Inc(ASize);
    until AShift + ASize >= 32;
  end;

  procedure ReadPalette(APaletteIsOS2: Boolean);
  var
    ColorSize: Byte;
    C: TColorRGBA;
    n, len, maxlen: Integer;
  begin
    SetLength(FPalette, 0);
    if Info.PaletteCount = 0 then Exit;

    if APaletteIsOS2
    then ColorSize := 3
    else ColorSize := 4;

    if FDibInfo.BitCount > 8
    then begin
      // Bitmaps can have a color table stored in the palette entries,
      // skip them, since we don't use it
      TheStream.Seek(Info.PaletteCount * ColorSize, soCurrent);
      Exit;
    end;

    maxlen := 1 shl Info.BitCount;
    if Info.PaletteCount <= maxlen
    then len := maxlen
    else len := Info.PaletteCount; // more colors ???

    SetLength(FPalette, len);

    for n := 0 to Info.PaletteCount - 1 do
    begin
      TheStream.Read(C, ColorSize);
      C.A := $FF; //palette has no alpha
      FPalette[n] := RGBToFPColor(C);
    end;

    // fill remaining with black color, so we don't have to check for out of index values
    for n := Info.PaletteCount to maxlen - 1 do
      FPalette[n] := colBlack;
  end;

var
  BIH: TBitmapInfoHeader;
  BCH: TBitmapCoreHeader;
  H: Integer;
  StreamStart: Int64;
begin
  StreamStart := theStream.Position;
  TheStream.Read(BIH.biSize,SizeOf(BIH.biSize));
  {$IFDEF FPC_BIG_ENDIAN}
  BIH.biSize := LEtoN(BIH.biSize);
  {$ENDIF}

  if BIH.biSize = 12
  then begin
    // OS2 V1 header
    TheStream.Read(BCH.bcWidth, BIH.biSize - SizeOf(BIH.biSize));

    FDibInfo.Width := LEtoN(BCH.bcWidth);
    FDibInfo.Height := LEtoN(BCH.bcHeight);
    FDibInfo.BitCount := LEtoN(BCH.bcBitCount);
    FDibInfo.Encoding := lrdeRGB;
    FDibInfo.UpsideDown := True;

    if FDibInfo.BitCount > 8
    then FDibInfo.PaletteCount := 0
    else FDibInfo.PaletteCount := 1 shl FDibInfo.BitCount;
  end
  else begin
    // Windows Vx header or OSX V2, all start with BitmapInfoHeader
    TheStream.Read(BIH.biWidth, SizeOf(BIH) - SizeOf(BIH.biSize));

    FDibInfo.Width := LEtoN(BIH.biWidth);
    H := LEtoN(BIH.biHeight);
    // by default bitmaps are stored upside down
    if H >= 0
    then begin
      FDibInfo.UpsideDown := True;
      FDibInfo.Height := H;
    end
    else begin
      FDibInfo.UpsideDown := False;
      FDibInfo.Height := -H;
    end;

    FDibInfo.BitCount := LEtoN(BIH.biBitCount);
    case LEtoN(BIH.biCompression) of
      BI_RGB        : FDibInfo.Encoding := lrdeRGB;
      4, {BCA_RLE24}
      BI_RLE8,
      BI_RLE4       : FDibInfo.Encoding := lrdeRLE;
      {BCA_HUFFMAN1D, }
      BI_BITFIELDS  : begin
        // OS2 can use huffman encoding for mono bitmaps
        // bitfields only work for 16 and 32
        if FDibInfo.BitCount = 1
        then FDibInfo.Encoding := lrdeHuffman
        else FDibInfo.Encoding := lrdeBitfield;
      end;
    else
      raise FPImageException.CreateFmt(SUnknownCompression, [LEtoN(BIH.biCompression)]);
    end;

    if not (FDibInfo.Encoding in [lrdeRGB, lrdeRLE, lrdeBitfield])
    then raise FPImageException.CreateFmt(SUnsupportedCompression, [SEncoding[FDibInfo.Encoding]]);

    FDibInfo.PaletteCount := LEtoN(BIH.biClrUsed);
    if  (FDibInfo.PaletteCount = 0)
    and (FDibInfo.BitCount <= 8)
    then FDibInfo.PaletteCount := 1 shl FDibInfo.BitCount;
  end;

  if not ValidCompression
  then raise FPImageException.CreateFmt(SWrongCombination, [FDibInfo.BitCount, SEncoding[FDibInfo.Encoding]]);

  if BIH.biSize >= 108
  then begin
    // at least a V4 header -> has alpha mask, which is always valid (read other masks too)
    TheStream.Read(FDibInfo.PixelMasks, 4 * SizeOf(FDibInfo.PixelMasks.R));
    GetMaskShiftSize(FDibInfo.PixelMasks.A, FDibInfo.MaskShift.A, FDibInfo.MaskSize.A);
  end
  else begin
    // officially no alpha support, but that breaks older LCL compatebility
    // so add it
    if Info.BitCount = 32
    then begin
      {$ifdef ENDIAN_BIG}
      FDibInfo.PixelMasks.A := $000000FF;
      {$else}
      FDibInfo.PixelMasks.A := $FF000000;
      {$endif}
      GetMaskShiftSize(FDibInfo.PixelMasks.A, FDibInfo.MaskShift.A, FDibInfo.MaskSize.A);
    end
    else begin
      FDibInfo.PixelMasks.A := 0;
      FDibInfo.MaskShift.A := 0;
      FDibInfo.MaskSize.A := 0;
    end;
  end;

  if Info.Encoding = lrdeBitfield
  then begin
    if BIH.biSize < 108
    then begin
      // not read yet
      TheStream.Read(FDibInfo.PixelMasks, 3 * SizeOf(FDibInfo.PixelMasks.R));
      // check if added mask is valid
      if (Info.PixelMasks.R or Info.PixelMasks.G or Info.PixelMasks.B) and Info.PixelMasks.A <> 0
      then begin
        // Alpha mask overlaps others
        FDibInfo.PixelMasks.A := 0;
        FDibInfo.MaskShift.A := 0;
        FDibInfo.MaskSize.A := 0;
      end;
    end;
    GetMaskShiftSize(FDibInfo.PixelMasks.R, FDibInfo.MaskShift.R, FDibInfo.MaskSize.R);
    GetMaskShiftSize(FDibInfo.PixelMasks.G, FDibInfo.MaskShift.G, FDibInfo.MaskSize.G);
    GetMaskShiftSize(FDibInfo.PixelMasks.B, FDibInfo.MaskShift.B, FDibInfo.MaskSize.B);

    TheStream.Seek(StreamStart + BIH.biSize, soBeginning);
  end
  else begin
    TheStream.Seek(StreamStart + BIH.biSize, soBeginning);
    ReadPalette(BIH.biSize = 12);
  end;

  //if Info.MaskSize.A <> 0 {Info.BitCount = 32}
  //then CheckAlphaDescription(TheImage);
end;

function TLazReaderDIB.QueryInterface(constref iid: TGuid; out obj): longint; {$IFDEF WINDOWs}stdcall{$ELSE}cdecl{$ENDIF};
begin
  if GetInterface(iid, obj)
  then Result := S_OK
  else Result := E_NOINTERFACE;
end;

procedure TLazReaderDIB.InternalReadBody;


  procedure SaveTransparentColor;
  begin
    if FMaskMode <> lrmmAuto then Exit;

    // define transparent color: 1-8 use palette, 15-24 use fixed color
    case Info.BitCount of
      1: FMaskIndex := (LineBuf[0] shr 7) and 1;
      4: FMaskIndex := (LineBuf[0] shr 4) and $f;
      8: FMaskIndex := LineBuf[0];
    else
      FMaskIndex := -1;
      if Info.Encoding = lrdeBitfield
      then begin
        FMaskColor := BitfieldsToFPColor(PCardinal(LineBuf)[0]);
        Exit;
      end;

      case Info.BitCount of
        16: FMaskColor := RGBToFPColor({$ifdef FPC_BIG_ENDIAN}LeToN{$endif}(PWord(LineBuf)[0]));
        24: FMaskColor := RGBToFPColor(PColorRGB(LineBuf)[0]);
        32: FMaskColor := RGBToFPColor(PColorRGBA(LineBuf)[0]);
      end;

      Exit;
    end;
    if FMaskIndex <> -1
    then FMaskColor := FPalette[FMaskIndex];
  end;

  procedure UpdateProgress(Row: Integer); inline;
  begin
    Progress(psRunning, trunc(100.0 * ((TheImage.Height - Row) / TheImage.Height)),
      False, Rect(0, 0, TheImage.Width - 1, TheImage.Height - 1 - Row), 'reading BMP pixels', FContinue);
  end;

var
  Row : Cardinal;
begin
  TheImage.SetSize(Info.Width, Info.Height);

  if Info.Height = 0 then Exit;
  if Info.Width = 0 then Exit;

  InitLineBuf;
  try
    if not FContinue then Exit;

    Row := Info.Height - 1;
    ReadScanLine(Row);
    SaveTransparentColor;

    if Info.UpsideDown
    then WriteScanLine(Row)
    else WriteScanLine(Info.Height - 1 - Row);

    UpdateProgress(Row);

    while Row > 0 do
    begin
      if not FContinue then Exit;
      Dec(Row);
      ReadScanLine(Row); // Scanline in LineBuf with Size ReadSize.

      if Info.UpsideDown
      then WriteScanLine(Row)
      else WriteScanLine(Info.Height - 1 - Row);

      UpdateProgress(Row);
    end;
  finally
    FreeLineBuf;
  end;
end;

function TLazReaderDIB.InternalCheck(Stream: TStream): boolean;
begin
  Result := True;
end;

constructor TLazReaderDIB.Create;
begin
  inherited Create;
  FMaskColor := colTransparent;
  FContinue := True;
end;

destructor TLazReaderDIB.Destroy;
begin
  FreeLineBuf;
  inherited Destroy;
end;


end.


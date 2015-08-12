unit DwgPreview;
interface
uses
  Windows, Messages, SysUtils, Classes, Controls, ExtCtrls;
type
  TDwgPreview = class(TImage)
  private
    FFileName: string;
    procedure SetFileName(Value: string);
    procedure ImportDwgThumbnail(DWGFileName: string);
  protected
    { Protected declarations }
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property FileName: string read FFileName write SetFileName;
  end;
procedure Register;
implementation
constructor TDwgPreview.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
end;
destructor TDwgPreview.Destroy;
begin
  inherited Destroy;
end;
procedure TDwgPreview.SetFileName(Value: string);
begin
  FFileName := Value;
  ImportDwgThumbnail(pchar(Value));
end;
procedure TDwgPreview.ImportDwgThumbnail(DWGFileName: string);
const
  ImageSentinel: array[0..15] of Byte =
  ($1F, $25, $6D, $07, $D4, $36, $28, $28, $9D, $57, $CA, $3F, $9D, $44, $10,
    $2B);
type
  TDwgFileHeader = packed record
    Signature: array[0..5] of AnsiChar;
    Unused: array[0..6] of AnsiChar;
    ImageSeek: LongInt;
  end;
var
  DwgFile: file;
  StoreFileMode: Byte;
  DwgFileHeader: TDwgFileHeader;
  DwgSentinelData: array[0..15] of Byte;
  function LoadBMPData(const BitmapInfo: PBitmapInfo): Boolean;
  var
    BitmapHandle: HBITMAP;
    Bits: Pointer;
    NumColors: Integer;
    DC: HDC;
    function GetDInColors(BitCount: Word): Integer;
    begin
      case BitCount of
        1, 4, 8: Result := 1 shl BitCount;
      else
        Result := 0;
      end;
    end;
  begin
    Result := False;
    DC := GetDC(0);
    if DC = 0 then
      Exit;
    try
      with BitmapInfo^ do
      begin
        NumColors := GetDInColors(bmiHeader.biBitCount);
        Bits := Pointer(Longint(BitmapInfo) + SizeOf(bmiHeader) + NumColors *
          SizeOf(TRGBQuad));
      end;
      BitmapHandle := CreateDIBitmap(DC, BitmapInfo.bmiHeader, CBM_INIT, Bits,
        BitmapInfo^, DIB_RGB_COLORS);
      if BitmapHandle <> 0 then
      begin
         inherited Picture.Bitmap.Handle := BitmapHandle;
         inherited Show;
        Result := True;
      end;
    finally
      ReleaseDC(0, DC);
    end;
  end;
  procedure ProcessImageData;
  type
    TImageDataHeader = packed record
      TotalCount: LongInt;
      ImagesPresent: Byte;
    end;
    TImageDataRecord = packed record
      DataType: Byte;
      StartOfData: LongInt;
      SizeOfData: LongInt;
    end;
  var
    ImageHeader: TImageDataHeader;
    ImageRecord: TImageDataRecord;
    BMPData, WMFData: TImageDataRecord;
    ThumbData: Pointer;
  begin
    BlockRead(DwgFile, ImageHeader, SizeOf(ImageHeader));
    if ImageHeader.TotalCount + FilePos(DwgFile) > FileSize(DwgFile) then
      Exit;
    FillChar(BMPData, SizeOf(BMPData), 0);
    FillChar(WMFData, SizeOf(WMFData), 0);
    while (IOResult = 0) and (ImageHeader.ImagesPresent > 0) do
    begin
      BlockRead(DwgFile, ImageRecord, SizeOf(ImageRecord));
      if (IOResult <> 0) or (ImageRecord.StartOfData > FileSize(DwgFile)) then
        Break;
      case ImageRecord.DataType of
        2: BMPData := ImageRecord;
        3: WMFData := ImageRecord;
      end;
      Dec(ImageHeader.ImagesPresent);
    end;
    if BMPData.StartOfData > 0 then
      ImageRecord := BMPData
    else
      Exit;
    Seek(DwgFile, ImageRecord.StartOfData);
    GetMem(ThumbData, ImageRecord.SizeOfData);
    BlockRead(DwgFile, ThumbData^, ImageRecord.SizeOfData);
    try
        LoadBMPData(ThumbData);
    finally
      FreeMem(ThumbData);
    end;
  end;
begin
  Visible:=False;
  StoreFileMode := FileMode;
  FileMode := 0;
  System.Assign(DwgFile, DWGFileName);
  Reset(DwgFile, 1);
  FileMode := StoreFileMode;
  if IOResult <> 0 then
    Exit;
  try
    BlockRead(DwgFile, DwgFileHeader, SizeOf(DwgFileHeader));
    if (IOResult = 0) and (Copy(DwgFileHeader.Signature, 1, 4) = 'AC10') and
      (DwgFileHeader.ImageSeek <= FileSize(DwgFile)) then
    begin
      Seek(DwgFile, DwgFileHeader.ImageSeek);
      BlockRead(DwgFile, DwgSentinelData, SizeOf(DwgSentinelData));
      if (IOResult = 0) and CompareMem(@DwgSentinelData, @ImageSentinel,
        SizeOf(DwgSentinelData)) then
        ProcessImageData;
    end;
  finally
    Close(DwgFile);
  end;
end;
procedure Register;
begin
  RegisterComponents('Acad', [TDwgPreview]);
end;
end.
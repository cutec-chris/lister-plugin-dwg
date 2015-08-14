library dwgfile;

{$mode objfpc}{$H+}
{$include calling.inc}

uses
  Classes,
  sysutils,
  WLXPlugin,
  FPimage,FPReadBMP, DIBImageReader,FPWritePNG;

procedure ListGetDetectString(DetectString:pchar;maxlen:integer); dcpcall;
begin
  StrCopy(DetectString, 'EXT="DWG"');
end;

type
  TDwgFileHeader = packed record
    Signature: array[0..5] of AnsiChar;
    Unused: array[0..6] of AnsiChar;
    ImageSeek: LongInt;
  end;
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

function ListGetText(FileToLoad:pchar;contentbuf:pchar;contentbuflen:integer):pchar; dcpcall;
begin
end;

function ListGetPreviewBitmapFile(FileToLoad:pchar;OutputPath:pchar;width,height:integer;
    contentbuf:pchar;contentbuflen:integer):pchar; dcpcall;
const
  ImageSentinel: array[0..15] of Byte =
  ($1F, $25, $6D, $07, $D4, $36, $28, $28, $9D, $57, $CA, $3F, $9D, $44, $10,
    $2B);
var
  DwgFile: file;
  StoreFileMode: Byte;
  DwgFileHeader: TDwgFileHeader;
  DwgSentinelData: array[0..15] of Byte;
  OK: Boolean;
  Stream: TFileStream;
  ImageRecord: TImageDataRecord;
  aImage: TFPMemoryImage;
  aHandler: TLazReaderDIB;

  function ProcessImageData : Boolean;
  var
    ImageHeader: TImageDataHeader;
    BMPData, WMFData: TImageDataRecord;
  begin
    result := False;
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
    Result := True;
  end;
begin
  Result := '';
  StoreFileMode := FileMode;
  FileMode := 0;
  System.Assign(DwgFile, FileToLoad);
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
      if (IOResult = 0) and CompareMem(@DwgSentinelData, @ImageSentinel, SizeOf(DwgSentinelData)) then
        OK := ProcessImageData;
    end;
  finally
    Close(DwgFile);
  end;
  if OK then
    begin
      try
        Stream := TFileStream.Create(FileToLoad,fmOpenRead);
        Stream.Position:=ImageRecord.StartOfData;
        aImage := TFPMemoryImage.create(0,0);
        aHandler := TLazReaderDIB.Create;
        aImage.LoadFromStream(Stream,aHandler);
        aImage.SaveToFile(OutputPath+'thumb.png');
        Result := PChar(OutputPath+'thumb.png');
      finally
        aHandler.Free;
        aImage.Free;
        Stream.Free;
      end;
    end;
end;

exports
  ListGetDetectString,
  ListGetText,
  ListGetPreviewBitmapFile;

begin
end.


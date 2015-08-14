// Lister API definitions.
// This unit is written by Christian Ghisler, it's from Total Commander
// Lister API Guide, which can be found at http://ghisler.com.
// Version: 1.8.

unit WLXPlugin;

interface

{$IFDEF MSWINDOWS}
uses
Windows;{$ENDIF}

const
  lc_copy=1;
  lc_newparams=2;
  lc_selectall=3;
  lc_setpercent=4;
  lcp_wraptext=1;
  lcp_fittowindow=2;
  lcp_ansi=4;
  lcp_ascii=8;
  lcp_variable=12;
  lcp_forceshow=16;
  lcp_fitlargeronly=32;
  lcp_center=64;
  lcs_findfirst=1;
  lcs_matchcase=2;
  lcs_wholewords=4;
  lcs_backwards=8;
  itm_percent=$FFFE;
  itm_fontstyle=$FFFD;
  itm_wrap=$FFFC;
  itm_fit=$FFFB;
  itm_next=$FFFA;
  itm_center=$FFF9;
  LISTPLUGIN_OK=0;
  LISTPLUGIN_ERROR=1;

const MAX_PATH=32000;

type
  tListDefaultParamStruct=record
    size,
    PluginInterfaceVersionLow,
    PluginInterfaceVersionHi:longint;
    DefaultIniName:array[0..MAX_PATH-1] of char;
  end;

  pListDefaultParamStruct=^tListDefaultParamStruct;

type tdateformat=record
       wYear,wMonth,wDay:word;
     end;
     pdateformat=^tdateformat;

type ttimeformat=record
       wHour,wMinute,wSecond:word;
     end;
     ptimeformat=^ttimeformat;

type HBITMAP = type LongWord;

 { Function prototypes: Functions need to be defined exactly like this!}

 {
 function ListLoad(ParentWin:thandle;FileToLoad:pchar;ShowFlags:integer):thandle; dcpcall;
 function ListLoadW(ParentWin:thandle;FileToLoad:pwidechar;ShowFlags:integer):thandle; dcpcall;
 function ListLoadNext(ParentWin,PluginWin:thandle;FileToLoad:pchar;ShowFlags:integer):integer; dcpcall;
 function ListLoadNextW(ParentWin,PluginWin:thandle;FileToLoad:pwidechar;ShowFlags:integer):integer; dcpcall;
 procedure ListCloseWindow(ListWin:thandle); dcpcall;
 procedure ListGetDetectString(DetectString:pchar;maxlen:integer); dcpcall;
 function ListSearchText(ListWin:thandle;SearchString:pchar;
                         SearchParameter:integer):integer; dcpcall;
 function ListSearchTextW(ListWin:thandle;SearchString:pwidechar;
                         SearchParameter:integer):integer; dcpcall;
 function ListGetText(FileToLoad:pchar;contentbuf:pchar;contentbuflen:integer):pchar; dcpcall;
 function ListGetTextW(FileToLoad:pchar;contentbuf:pchar;contentbuflen:integer):pchar; dcpcall;
 function ListSearchDialog(ListWin:thandle;FindNext:integer):integer; dcpcall;
 function ListSendCommand(ListWin:thandle;Command,Parameter:integer):integer; dcpcall;
 function ListPrint(ListWin:thandle;FileToPrint,DefPrinter:pchar;
                    PrintFlags:integer;var Margins:trect):integer; dcpcall;
 function ListPrintW(ListWin:thandle;FileToPrint,DefPrinter:pwidechar;
                    PrintFlags:integer;var Margins:trect):integer; dcpcall;
 function ListNotificationReceived(ListWin:thandle;Message,wParam,lParam:integer):integer; dcpcall;
 procedure ListSetDefaultParams(dps:pListDefaultParamStruct); dcpcall;
 function ListGetPreviewBitmap(FileToLoad:pchar;width,height:integer;
     contentbuf:pchar;contentbuflen:integer):hbitmap; dcpcall;
 function ListGetPreviewBitmapFile(FileToLoad:pchar;width,height:integer;
     contentbuf:pchar;contentbuflen:integer):pchar; dcpcall;
 function ListGetPreviewBitmapW(FileToLoad:pwidechar;OutputPath:pchar;width,height:integer;
     contentbuf:pchar;contentbuflen:integer):hbitmap; dcpcall;
 function ListGetPreviewBitmapFileW(FileToLoad:pwidechar;OutputPath:pwidechar;width,height:integer;
     contentbuf:pchar;contentbuflen:integer):pchar; dcpcall;
 }


implementation

end.

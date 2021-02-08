unit Apollo_MVC_Core;

interface

type
  TControllerAbstract = class;
  TViewEventProc = procedure(const aEventName: string; aView: TObject) of object;
  TViewEventHandleProc = procedure(aView: TObject) of object;

  IViewBase = interface
  ['{DFCD4E01-FA56-4205-98A2-5CA0980651BB}']
    function GetEventProc: TViewEventProc;
    procedure FireEvent(const aEventName: string);
    procedure SetEventProc(aValue: TViewEventProc);
    property EventProc: TViewEventProc read GetEventProc write SetEventProc;
  end;

  IViewMain = interface
  ['{74EC0641-006A-4ED6-97A8-16DFA889EC75}']
    function SubscribeController: TControllerAbstract;
  end;

  TViewBase = class(TInterfacedObject, IViewBase)
  private
    FEventProc: TViewEventProc;
    FView: TObject;
    function GetEventProc: TViewEventProc;
    procedure FireEvent(const aEventName: string);
    procedure SetEventProc(aValue: TViewEventProc);
  public
    constructor Create(aView: TObject);
  end;

  TControllerAbstract = class abstract
  public
    procedure ViewEventsObserver(const aEventName: string; aView: TObject);
  end;

implementation

uses
  System.SysUtils;

{ TControllerAbstract }

procedure TControllerAbstract.ViewEventsObserver(const aEventName: string;
  aView: TObject);
var
  ViewEventHandleProc: TViewEventHandleProc;
begin
  TMethod(ViewEventHandleProc).Code := Self.MethodAddress(aEventName);
  TMethod(ViewEventHandleProc).Data := Self;

  if Assigned(ViewEventHandleProc) then
    ViewEventHandleProc(aView)
  else
    raise Exception.Create('');
end;

{ TBaseView }

constructor TViewBase.Create(aView: TObject);
begin
  FView := aView;
end;

procedure TViewBase.FireEvent(const aEventName: string);
begin
  FEventProc(aEventName, FView);
end;

function TViewBase.GetEventProc: TViewEventProc;
begin
  Result := FEventProc;
end;

procedure TViewBase.SetEventProc(aValue: TViewEventProc);
begin
  FEventProc := aValue;
end;

end.

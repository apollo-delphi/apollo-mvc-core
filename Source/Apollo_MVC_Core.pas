unit Apollo_MVC_Core;

interface

uses
  System.Classes,
  System.Generics.Collections;

type
  IModelIO = interface
  ['{BC1D1100-7593-4AAF-BADE-68902C480EA2}']
    function Add(const aIndex: Integer; aValue: Variant): IModelIO;
    function AddObject(const aIndex: Integer; aObject: TObject): IModelIO;
    function Get(const aIndex: Integer): Variant;
    function GetObject(const aIndex: Integer): TObject;
  end;

  TControllerAbstract = class;
  TModelEventProc = procedure(const aEventName: string; aOutput: IModelIO) of object;
  TViewEventProc = procedure(const aEventName: string; aView: TObject) of object;

  IModel = interface
  ['{37C50BE9-755C-4827-871A-9F812F7169E8}']
    procedure Start;
  end;

  TModelAbstract = class abstract(TInterfacedObject, IModel)
  private
    FEventProc: TModelEventProc;
  protected
    FInput: IModelIO;
    function NewOutput: IModelIO;
    procedure FireEvent(const aEventName: string; aOutput: IModelIO);
    procedure Start; virtual; abstract;
  public
    constructor CreateByController(aInput: IModelIO; aModelEventProc: TModelEventProc);
  end;

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
  private
    FObjectStorage: TObjectDictionary<string, TObject>;
  protected
    FViews: TObjectDictionary<TClass, TComponent>;
    function ExtractFromStorage(const aKey: string): TObject;
    function GetFromStorage(const aKey: string): TObject;
    function GetView<T: TComponent>: T;
    function NewInput: IModelIO;
    procedure AfterCreate; virtual;
    procedure BeforeDestroy; virtual;
    procedure CallModel<T: TModelAbstract, constructor>(aInput: IModelIO; aThreadCount: Integer = 1); overload;
    procedure CallModel<T: TModelAbstract, constructor>(aThreadCount: Integer = 1); overload;
    procedure PutToStorage(const aKey: string; aObject: TObject);
  public
    procedure ModelEventsObserver(const aEventName: string; aOutput: IModelIO);
    procedure ViewEventsObserver(const aEventName: string; aView: TObject);
    constructor Create;
    destructor Destroy; override;
  end;

implementation

uses
  System.SysUtils,
  System.Threading;

type
  TModelEventHandleProc = procedure(aOutput: IModelIO) of object;
  TViewEventHandleProc = procedure(aView: TObject) of object;

  TModelIO = class(TInterfacedObject, IModelIO)
  strict private
    FObjects: TObjectDictionary<Integer, TObject>;
    FValues: TDictionary<Integer, Variant>;
    function Add(const aIndex: Integer; aValue: Variant): IModelIO;
    function AddObject(const aIndex: Integer; aObject: TObject): IModelIO;
    function Get(const aIndex: Integer): Variant;
    function GetObject(const aIndex: Integer): TObject;
    procedure AfterConstruction; override;
    procedure BeforeDestruction; override;
  end;

{ TModelAbstract }

constructor TModelAbstract.CreateByController(aInput: IModelIO; aModelEventProc: TModelEventProc);
begin
  FInput := aInput;
  FEventProc := aModelEventProc;
end;

procedure TModelAbstract.FireEvent(const aEventName: string; aOutput: IModelIO);
begin
  FEventProc(aEventName, aOutput);
end;

function TModelAbstract.NewOutput: IModelIO;
begin
  Result := TModelIO.Create;
end;

{ TControllerAbstract }

procedure TControllerAbstract.AfterCreate;
begin
end;

procedure TControllerAbstract.BeforeDestroy;
begin
end;

procedure TControllerAbstract.CallModel<T>(aThreadCount: Integer = 1);
begin
  CallModel<T>(nil, aThreadCount);
end;

procedure TControllerAbstract.CallModel<T>(aInput: IModelIO;
  aThreadCount: Integer);
var
  i: Integer;
  Model: IModel;
  Task: ITask;
begin
  for i := 0 to aThreadCount - 1 do
  begin
    Model := T.CreateByController(aInput, ModelEventsObserver);
    Task := TTask.Create(procedure()
      begin
        Model.Start
      end);
    Task.Start;
  end;
end;

constructor TControllerAbstract.Create;
begin
  inherited;

  FViews := TObjectDictionary<TClass, TComponent>.Create;
  FObjectStorage := TObjectDictionary<string, TObject>.Create([doOwnsValues]);

  AfterCreate;
end;

destructor TControllerAbstract.Destroy;
begin
  BeforeDestroy;

  FViews.Free;
  FObjectStorage.Free;

  inherited;
end;

function TControllerAbstract.ExtractFromStorage(const aKey: string): TObject;
var
  Pair: TPair<string, TObject>;
begin
  Pair := FObjectStorage.ExtractPair(aKey);
  Result := Pair.Value;
end;

function TControllerAbstract.GetFromStorage(const aKey: string): TObject;
begin
  Result := FObjectStorage.Items[aKey];
end;

function TControllerAbstract.GetView<T>: T;
var
  Value: TComponent;
begin
  if FViews.TryGetValue(T, Value) then
    Result := Value as T
  else
    raise Exception.CreateFmt('Controller %s View %s closed or did not create', [ClassName, T.ClassName]);
end;

procedure TControllerAbstract.ModelEventsObserver(const aEventName: string;
  aOutput: IModelIO);
var
  ModelEventHandleProc: TModelEventHandleProc;
begin
  TMethod(ModelEventHandleProc).Code := Self.MethodAddress(aEventName);
  TMethod(ModelEventHandleProc).Data := Self;

  if not Assigned(ModelEventHandleProc) then
    raise Exception.CreateFmt('Controller %s does not implement procedure %s', [ClassName, aEventName]);

  TThread.Synchronize(nil, procedure()
    begin
      ModelEventHandleProc(aOutput);
    end
  );
end;

function TControllerAbstract.NewInput: IModelIO;
begin
  Result := TModelIO.Create;
end;

procedure TControllerAbstract.PutToStorage(const aKey: string; aObject: TObject);
begin
  FObjectStorage.Add(aKey, aObject);
end;

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
    raise Exception.CreateFmt('Controller %s does not implement procedure %s', [ClassName, aEventName]);
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

{ TModelIO }

function TModelIO.Add(const aIndex: Integer; aValue: Variant): IModelIO;
begin
  FValues.Add(aIndex, aValue);
  Result := Self;
end;

function TModelIO.AddObject(const aIndex: Integer;
  aObject: TObject): IModelIO;
begin
  FObjects.Add(aIndex, aObject);
  Result := Self;
end;

procedure TModelIO.AfterConstruction;
begin
  inherited;

  FObjects := TObjectDictionary<Integer, TObject>.Create;
  FValues := TDictionary<Integer, Variant>.Create;
end;

procedure TModelIO.BeforeDestruction;
begin
  inherited;

  FObjects.Free;
  FValues.Free;
end;

function TModelIO.Get(const aIndex: Integer): Variant;
begin
  Result := FValues.Items[aIndex];
end;

function TModelIO.GetObject(const aIndex: Integer): TObject;
begin
  Result := FObjects.Items[aIndex];
end;

end.

unit Apollo_MVC_Core;

interface

uses
  Apollo_Types,
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
  TFreeNotificationSubscriber = procedure(aFreeNotificationProc: TSimpleMethod) of object;

  IModel = interface
  ['{37C50BE9-755C-4827-871A-9F812F7169E8}']
    procedure Cancel;
    procedure Start;
  end;

  TModelAbstract = class abstract(TInterfacedObject, IModel)
  private
    FEventProc: TModelEventProc;
    procedure Cancel;
    procedure OnControllerDestroy;
  protected
    FCancelled: Boolean;
    FInput: IModelIO;
    function NewOutput: IModelIO;
    procedure CheckCancel;
    procedure FireEvent(const aEventName: string; aOutput: IModelIO);
    procedure OnCancel; virtual;
    procedure Start; virtual; abstract;
  public
    constructor CreateByController(aInput: IModelIO; aModelEventProc: TModelEventProc;
      aFreeNotificationSubscriber: TFreeNotificationSubscriber);
  end;

  TModelClass = class of TModelAbstract;

  IViewBase = interface
  ['{DFCD4E01-FA56-4205-98A2-5CA0980651BB}']
    function GetEventProc: TViewEventProc;
    procedure FireEvent(const aEventName: string);
    procedure SetEventProc(aValue: TViewEventProc);
    property EventProc: TViewEventProc read GetEventProc write SetEventProc;
  end;

  TModelItem = record
    Index: Integer;
    Model: IModel;
    ModelClass: TModelClass;
  end;

  TModelsHelper = record helper for TArray<TModelItem>
    procedure Add(aModel: IModel; aModelClass: TModelClass; const aIndex: Integer);
  end;

  TControllerAbstract = class abstract
  private
    FFreeNotifications: TSimpleMethods;
    FModels: TArray<TModelItem>;
    FObjectStorage: TObjectDictionary<string, TObject>;
    procedure FreeNotificationSubscriber(aFreeNotificationProc: TSimpleMethod);
  protected
    FViews: TObjectDictionary<TClass, TComponent>;
    function ExtractFromStorage(const aKey: string): TObject;
    function GetFromStorage<T: class>(const aKey: string): T;
    function GetView<T: TComponent>: T;
    function NewInput: IModelIO;
    function TryGetModel<T: TModelAbstract>(out aModel: IModel; const aIndex: Integer = 0): Boolean;
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

  function MakeViewBase(aOwner: TObject): IViewBase;

implementation

uses
  System.SysUtils,
  System.Threading;

type
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

function MakeViewBase(aOwner: TObject): IViewBase;
begin
  Result := TViewBase.Create(aOwner);
end;

{ TModelAbstract }

procedure TModelAbstract.Cancel;
begin
  FCancelled := True;
end;

constructor TModelAbstract.CreateByController(aInput: IModelIO; aModelEventProc: TModelEventProc;
  aFreeNotificationSubscriber: TFreeNotificationSubscriber);
begin
  FInput := aInput;
  FEventProc := aModelEventProc;
  aFreeNotificationSubscriber(OnControllerDestroy);
end;

procedure TModelAbstract.FireEvent(const aEventName: string; aOutput: IModelIO);
begin
  if not FCancelled then
    FEventProc(aEventName, aOutput);
end;

function TModelAbstract.NewOutput: IModelIO;
begin
  Result := TModelIO.Create;
end;

procedure TModelAbstract.OnControllerDestroy;
begin
  FCancelled := True;
end;

procedure TModelAbstract.CheckCancel;
begin
  if FCancelled then
  begin
    OnCancel;
    Abort;
  end;
end;

procedure TModelAbstract.OnCancel;
begin
end;

{ TControllerAbstract }

procedure TControllerAbstract.AfterCreate;
begin
end;

procedure TControllerAbstract.BeforeDestroy;
begin
  FFreeNotifications.Exec;
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
    Model := T.CreateByController(aInput, ModelEventsObserver, FreeNotificationSubscriber);
    Task := TTask.Create(procedure()
      begin
        Model.Start
      end);

    FModels.Add(Model, T, i);
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

procedure TControllerAbstract.FreeNotificationSubscriber(
  aFreeNotificationProc: TSimpleMethod);
begin
  FFreeNotifications.Add(aFreeNotificationProc);
end;

function TControllerAbstract.GetFromStorage<T>(const aKey: string): T;
begin
  Result := FObjectStorage.Items[aKey] as T;
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

function TControllerAbstract.TryGetModel<T>(out aModel: IModel; const aIndex: Integer = 0): Boolean;
var
  ModelItem: TModelItem;
begin
  Result := False;

  for ModelItem in FModels do
    if (ModelItem.ModelClass = T) and (ModelItem.Index = aIndex) then
    begin
      aModel := ModelItem.Model;
      Exit(True);
    end;
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

{TModelsHelper}

procedure TModelsHelper.Add(aModel: IModel; aModelClass: TModelClass; const aIndex: Integer);
var
  ModelItem: TModelItem;
begin
  ModelItem.Model := aModel;
  ModelItem.ModelClass := aModelClass;
  ModelItem.Index := aIndex;

  Self := Self + [ModelItem];
end;

end.

unit Apollo_MVC_Core;

interface

uses
  System.Classes,
  System.Generics.Collections,
  System.Threading;

type
  IModelIO = interface
  ['{BC1D1100-7593-4AAF-BADE-68902C480EA2}']
    function Add(const aIndex: Integer; aValue: Variant): IModelIO;
    function AddObject(const aIndex: Integer; aObject: TObject): IModelIO;
    function Get(const aIndex: Integer): Variant;
    function GetModelClassType: TClass;
    function GetObject(const aIndex: Integer): TObject;
    property ModelClassType: TClass read GetModelClassType;
  end;

  TControllerAbstract = class;
  TControllerClass = class of TControllerAbstract;
  TInitProc = procedure of object;
  TModelEventProc = procedure(const aEventName: string; aOutput: IModelIO) of object;
  TRememberEventProc = procedure(aView: TComponent; const aPropName: string; const aValue: Variant) of object;
  TViewEventProc = procedure(const aEventName: string; aView: TComponent) of object;
  TViewRecoverProc = procedure(const aPropName: string; aValue: Variant) of object;

  IModel = interface
  ['{37C50BE9-755C-4827-871A-9F812F7169E8}']
    procedure Cancel;
    procedure Start;
  end;

  TModelAbstract = class abstract(TInterfacedObject, IModel)
  private
    FEventProc: TModelEventProc;
    procedure Cancel;
  protected
    FCancelled: Boolean;
    FInput: IModelIO;
    function NewOutput: IModelIO;
    procedure CheckCanceled;
    procedure FireEvent(const aEventName: string; aOutput: IModelIO);
    procedure BeforeDestroy; virtual;
    procedure OnCancel; virtual;
    procedure Start; virtual; abstract;
  public
    constructor CreateByController(aInput: IModelIO; aModelEventProc: TModelEventProc);
    destructor Destroy; override;
  end;

  TModelClass = class of TModelAbstract;

  IViewBase = interface
  ['{DFCD4E01-FA56-4205-98A2-5CA0980651BB}']
    function EncodeNumProp(const aKey: string; const aNum: Integer): string;
    function GetEventProc: TViewEventProc;
    function GetOnInitControls: TInitProc;
    function GetOnInitVariables: TInitProc;
    function GetOnRecover: TViewRecoverProc;
    function GetRememberEventProc: TRememberEventProc;
    function GetView: TComponent;
    function TryGetNumProp(const aPropName, aKey: string; out aNum: Integer): Boolean;
    procedure FireEvent(const aEventName: string);
    procedure Recover(const aPropName: string; aValue: string);
    procedure RegisterInController(aController: TControllerAbstract);
    procedure Remember(const aPropName: string; const aValue: Variant);
    procedure SetEventProc(aValue: TViewEventProc);
    procedure SetOnInitControls(aValue: TInitProc);
    procedure SetOnInitVariables(aValue: TInitProc);
    procedure SetOnRecover(aValue: TViewRecoverProc);
    procedure SetRememberEventProc(aValue: TRememberEventProc);
    property EventProc: TViewEventProc read GetEventProc write SetEventProc;
    property OnInitControls: TInitProc read GetOnInitControls write SetOnInitControls;
    property OnInitVariables: TInitProc read GetOnInitVariables write SetOnInitVariables;
    property OnRecover: TViewRecoverProc read GetOnRecover write SetOnRecover;
    property RememberEventProc: TRememberEventProc read GetRememberEventProc write SetRememberEventProc;
    property View: TComponent read GetView;
  end;

  TModelItem = record
    Index: Integer;
    [weak] Model: IModel;
    ModelClass: TModelClass;
    [weak] Task: ITask;
  end;

  TModelsHelper = record helper for TArray<TModelItem>
    function GetTasks: TArray<ITask>;
    procedure Add(aModel: IModel; aModelClass: TModelClass; const aIndex: Integer; aTask: ITask);
    procedure CancelAll;
    procedure Remove(aModelClass: TClass);
  end;

  TControllerAbstract = class abstract
  private
    FControllers: TObjectList<TControllerAbstract>;
    FIsMain: Boolean;
    FModels: TArray<TModelItem>;
    FObjectStorage: TObjectDictionary<string, TObject>;
    FRememberList: TStringList;
    FViews: TObjectDictionary<TClass, TComponent>;
    function GetRememberList: TStringList;
    function GetRowKey(const aViewName, aPropName: string): string;
    procedure ModelEventsObserver(const aEventName: string; aOutput: IModelIO);
    procedure RecoverRemembers(aViewBase: IViewBase);
    procedure RegisterView(aViewBase: IViewBase);
    procedure ViewEventsObserver(const aEventName: string; aView: TComponent);
    procedure ViewRememberObserver(aView: TComponent; const aPropName: string; const aValue: Variant);
  protected
    function CreateView<T: TComponent>(aParentView: TComponent): T;
    function ExtractFromStorage<T: class>(const aKey: string): T;
    function GetFromStorage<T: class>(const aKey: string): T;
    function GetRememberFilePath: string; virtual;
    function NewInput: IModelIO;
    function TryGetFromStorage<T: class>(const aKey: string; out aValue: T): Boolean;
    function TryGetModel<T: TModelAbstract>(out aModel: IModel; const aIndex: Integer = 0): Boolean;
    function TryGetView<T: TComponent>(out aView: T): Boolean;
    procedure AfterCreate; virtual;
    procedure BeforeDestroy; virtual;
    procedure CallModel<T: TModelAbstract, constructor>(aInput: IModelIO; aThreadCount: Integer = 1); overload;
    procedure CallModel<T: TModelAbstract, constructor>(aThreadCount: Integer = 1); overload;
    procedure PutToStorage(const aKey: string; aObject: TObject);
    procedure RemoveFromStorage(aValue: TObject); overload;
    procedure RemoveFromStorage(const aKey: string); overload;
  public
    procedure RegisterChildController(aControllerClass: TControllerClass);
    constructor Create(const aIsMain: Boolean = True);
    destructor Destroy; override;
  end;

const
  mvcModelDestroy = 'mvcModelDestroy';
  mvcViewClose = 'mvcViewClose';
  mvcRegisterFrame = 'mvcRegisterFrame';
  mvcRemoverFrame = 'mvcRemoveFrame';

var
  gAllowDirectConstructorForView: Boolean;

  function MakeViewBase(aOwner: TComponent): IViewBase;

implementation

uses
  System.IOUtils,
  System.Rtti,
  System.SysUtils,
  System.TypInfo;

type
  TViewBase = class(TInterfacedObject, IViewBase)
  private
    FEventProc: TViewEventProc;
    FOnInitControls: TInitProc;
    FOnInitVariables: TInitProc;
    FOnRecover: TViewRecoverProc;
    FRememberEventProc: TRememberEventProc;
    FView: TComponent;
    function EncodeNumProp(const aKey: string; const aNum: Integer): string;
    function GetEventProc: TViewEventProc;
    function GetOnInitControls: TInitProc;
    function GetOnInitVariables: TInitProc;
    function GetOnRecover: TViewRecoverProc;
    function GetRememberEventProc: TRememberEventProc;
    function GetView: TComponent;
    function TryGetNumProp(const aPropName, aKey: string; out aNum: Integer): Boolean;
    procedure FireEvent(const aEventName: string);
    procedure Recover(const aPropName: string; aValue: string);
    procedure RegisterInController(aController: TControllerAbstract);
    procedure Remember(const aPropName: string; const aValue: Variant);
    procedure SetEventProc(aValue: TViewEventProc);
    procedure SetOnInitControls(aValue: TInitProc);
    procedure SetOnInitVariables(aValue: TInitProc);
    procedure SetOnRecover(aValue: TViewRecoverProc);
    procedure SetRememberEventProc(aValue: TRememberEventProc);
  public
    constructor Create(aView: TComponent);
  end;

  TModelEventHandleProc = procedure(aOutput: IModelIO) of object;
  TViewEventHandleProc = procedure(aView: TObject) of object;

  TModelIO = class(TInterfacedObject, IModelIO)
  strict private
    FObjects: TObjectDictionary<Integer, TObject>;
    FValues: TDictionary<Integer, Variant>;
    FModelClassType: TClass;
    function Add(const aIndex: Integer; aValue: Variant): IModelIO;
    function AddObject(const aIndex: Integer; aObject: TObject): IModelIO;
    function GetModelClassType: TClass;
    function Get(const aIndex: Integer): Variant;
    function GetObject(const aIndex: Integer): TObject;
    procedure AfterConstruction; override;
    procedure BeforeDestruction; override;
  private
    constructor Create(aModelClassType: TClass);
  end;

function MakeViewBase(aOwner: TComponent): IViewBase;
begin
  Result := TViewBase.Create(aOwner);
end;

{ TModelAbstract }

procedure TModelAbstract.Cancel;
begin
  FCancelled := True;
end;

constructor TModelAbstract.CreateByController(aInput: IModelIO; aModelEventProc: TModelEventProc);
begin
  FInput := aInput;
  FEventProc := aModelEventProc;
end;

procedure TModelAbstract.FireEvent(const aEventName: string; aOutput: IModelIO);
begin
  if not FCancelled then
    FEventProc(aEventName, aOutput);
end;

function TModelAbstract.NewOutput: IModelIO;
begin
  Result := TModelIO.Create(ClassType);
end;

procedure TModelAbstract.CheckCanceled;
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

procedure TModelAbstract.BeforeDestroy;
begin
end;

destructor TModelAbstract.Destroy;
begin
  BeforeDestroy;
  FEventProc(mvcModelDestroy, NewOutput);

  inherited;
end;

{ TControllerAbstract }

procedure TControllerAbstract.AfterCreate;
begin
end;

procedure TControllerAbstract.BeforeDestroy;
begin
  FModels.CancelAll;
  TTask.WaitForAll(FModels.GetTasks);
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
        try
          Model.Start;
        except
          on E: EAbort do //do nothing
        else
          raise;
        end;
      end
    );

    FModels.Add(Model, T, i, Task);
    Task.Start;
  end;
end;

constructor TControllerAbstract.Create(const aIsMain: Boolean);
begin
  FIsMain := aIsMain;
  if FIsMain then
  begin
    FControllers := TObjectList<TControllerAbstract>.Create(False{aOwnsObjects});
    FControllers.Add(Self);
  end;

  FViews := TObjectDictionary<TClass, TComponent>.Create;
  FObjectStorage := TObjectDictionary<string, TObject>.Create([doOwnsValues]);

  AfterCreate;
end;

destructor TControllerAbstract.Destroy;
var
  ChildController: TControllerAbstract;
begin
  BeforeDestroy;

  if FIsMain then
  begin
    for ChildController in FControllers do
      if ChildController <> Self then
        ChildController.Free;

    FControllers.Free;
  end;

  if Assigned(FRememberList) then
    FRememberList.Free;
  FViews.Free;
  FObjectStorage.Free;

  inherited;
end;

function TControllerAbstract.ExtractFromStorage<T>(const aKey: string): T;
var
  Pair: TPair<string, TObject>;
begin
  Pair := FObjectStorage.ExtractPair(aKey);
  Result := Pair.Value as T;
end;

function TControllerAbstract.GetFromStorage<T>(const aKey: string): T;
begin
  Result := FObjectStorage.Items[aKey] as T;
end;

function TControllerAbstract.TryGetView<T>(out aView: T): Boolean;
var
  Controller: TControllerAbstract;
  Value: TComponent;
begin
  Result := False;

  for Controller in FControllers do
  begin
    if Controller.FViews.TryGetValue(T, Value) then
    begin
      aView := Value as T;
      Exit(True);
    end;
  end;
end;

procedure TControllerAbstract.ModelEventsObserver(const aEventName: string;
  aOutput: IModelIO);
var
  ModelEventHandleProc: TModelEventHandleProc;
begin
  if aEventName = mvcModelDestroy then
  begin
    FModels.Remove(aOutput.ModelClassType);
    Exit;
  end;

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

function TControllerAbstract.CreateView<T>(aParentView: TComponent): T;
var
  ViewBase: IViewBase;
begin
  gAllowDirectConstructorForView := True;
  try
    Result := T.Create(aParentView);
  finally
    gAllowDirectConstructorForView := False;
  end;

  if Result.GetInterface(IViewBase, ViewBase) then
    RegisterView(ViewBase)
  else
    raise Exception.CreateFmt('Create view error, class %s does not implement IViewBase interface', [T.ClassName]);
end;

function TControllerAbstract.NewInput: IModelIO;
begin
  Result := TModelIO.Create(nil);
end;

procedure TControllerAbstract.PutToStorage(const aKey: string; aObject: TObject);
begin
  FObjectStorage.Add(aKey, aObject);
end;

procedure TControllerAbstract.ViewEventsObserver(const aEventName: string;
  aView: TComponent);
var
  Controller: TControllerAbstract;
  ViewEventHandleProc: TViewEventHandleProc;
begin
  if (aEventName = mvcViewClose) or
     (aEventName = mvcRemoverFrame)
  then
  begin
    FViews.Remove(aView.ClassType);
    Exit;
  end
  else
  if aEventName = mvcRegisterFrame then
  begin
    FViews.AddOrSetValue(aView.ClassType, aView);;
    Exit;
  end;

  for Controller in FControllers do
  begin
    TMethod(ViewEventHandleProc).Code := Controller.MethodAddress(aEventName);
    TMethod(ViewEventHandleProc).Data := Controller;

    if Assigned(ViewEventHandleProc) then
    begin
      ViewEventHandleProc(aView);
      Exit;
    end;
  end;

  raise Exception.CreateFmt('TControllerAbstract.ViewEventsObserver: did not find procedure %s', [aEventName]);
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

procedure TControllerAbstract.RemoveFromStorage(const aKey: string);
var
  Value: TObject;
begin
  if FObjectStorage.TryGetValue(aKey, {out}Value) then
    FObjectStorage.Remove(aKey);
end;

procedure TControllerAbstract.RemoveFromStorage(aValue: TObject);
var
  Pair: TPair<string, TObject>;
begin
  for Pair in FObjectStorage do
    if Pair.Value = aValue then
    begin
      RemoveFromStorage(Pair.Key);
    end;
end;

function TControllerAbstract.TryGetFromStorage<T>(const aKey: string; out aValue: T): Boolean;
var
  Value: TObject;
begin
  Result := FObjectStorage.TryGetValue(aKey, {out}Value);
  if Result then
    aValue := Value as T;
end;

function TControllerAbstract.GetRememberList: TStringList;
begin
  if not Assigned(FRememberList) then
    FRememberList := TStringList.Create;

  Result := FRememberList;
end;

procedure TControllerAbstract.RegisterView(aViewBase: IViewBase);
begin
  FViews.AddOrSetValue(aViewBase.View.ClassType, aViewBase.View);

  aViewBase.OnInitVariables;
  RecoverRemembers(aViewBase);
  aViewBase.EventProc := ViewEventsObserver;
  aViewBase.RememberEventProc := ViewRememberObserver;
  aViewBase.OnInitControls;
end;

function TControllerAbstract.GetRememberFilePath: string;
begin
  Result := TPath.Combine(GetCurrentDir, 'app.ini');
end;

procedure TControllerAbstract.ViewRememberObserver(aView: TComponent;
  const aPropName: string; const aValue: Variant);
begin
  GetRememberList.Values[GetRowKey(aView.Name, aPropName)] := aValue;
  GetRememberList.SaveToFile(GetRememberFilePath);
end;

function TControllerAbstract.GetRowKey(const aViewName, aPropName: string): string;
begin
  Result := Format('%s.%s', [aViewName, aPropName]);
end;

procedure TControllerAbstract.RecoverRemembers(aViewBase: IViewBase);
var
  i: Integer;
  Key: TArray<string>;
begin
  if TFile.Exists(GetRememberFilePath) then
    GetRememberList.LoadFromFile(GetRememberFilePath);

  for i := 0 to GetRememberList.Count - 1 do
  begin
    Key := GetRememberList.KeyNames[i].Split(['.']);
    if Key[0] = aViewBase.View.Name then
      aViewBase.Recover(Key[1], GetRememberList.ValueFromIndex[i]);
  end;
end;

procedure TControllerAbstract.RegisterChildController(aControllerClass: TControllerClass);
var
  ChildController: TControllerAbstract;
begin
  ChildController := aControllerClass.Create(False{aIsMain});
  ChildController.FControllers := FControllers;

  FControllers.Add(ChildController);
end;

{ TBaseView }

procedure TViewBase.SetOnInitControls(aValue: TInitProc);
begin
  FOnInitControls := aValue;
end;

procedure TViewBase.SetOnInitVariables(aValue: TInitProc);
begin
  FOnInitVariables := aValue;
end;

function TViewBase.GetOnInitControls: TInitProc;
begin
  Result := FOnInitControls;
end;

function TViewBase.GetOnInitVariables: TInitProc;
begin
  Result := FOnInitVariables;
end;

function TViewBase.EncodeNumProp(const aKey: string; const aNum: Integer): string;
begin
  Result := Format('%s_%d', [aKey, aNum]);
end;

function TViewBase.TryGetNumProp(const aPropName, aKey: string; out aNum: Integer): Boolean;
var
  Words: TArray<string>;
begin
  Result := False;

  Words := aPropName.Split(['_']);
  if (Length(Words) > 1) and (Words[0] = aKey) then
  begin
    aNum := StrToIntDef(Words[High(Words)], -1);
    if aNum > -1 then
      Result := True;
  end;
end;

constructor TViewBase.Create(aView: TComponent);
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

procedure TViewBase.Remember(const aPropName: string; const aValue: Variant);
begin
  if Assigned(FRememberEventProc) then
    FRememberEventProc(FView, aPropName, aValue);
end;

procedure TViewBase.RegisterInController(aController: TControllerAbstract);
begin
  aController.RegisterView(Self);
end;

procedure TViewBase.Recover(const aPropName: string; aValue: string);
var
  IntValue: Integer;
  RttiContext: TRttiContext;
  RttiProperty: TRttiProperty;
  RttiType: TRttiType;
  Value: TValue;
  VarValue: Variant;
begin
  RttiContext := TRttiContext.Create;
  try
    RttiType := RttiContext.GetType(FView.ClassType);
    RttiProperty := RttiType.GetProperty(aPropName);
    if Assigned(RttiProperty) then
    begin
      case RttiProperty.PropertyType.TypeKind of
        tkInteger: Value := TValue.From<Integer>(aValue.ToInteger);
        tkEnumeration: Value := TValue.FromOrdinal(RttiProperty.PropertyType.Handle, aValue.ToInteger);
      else
        Value := TValue.From<string>(aValue);
      end;

      RttiProperty.SetValue(FView, Value);
      Exit;
    end;
  finally
    RttiContext.Free;
  end;

  if TryStrToInt(aValue, {out}IntValue) then
    VarValue := IntValue
  else
    VarValue := aValue;

  FOnRecover(aPropName, VarValue);
end;

function TViewBase.GetRememberEventProc: TRememberEventProc;
begin
  Result := FRememberEventProc;
end;

procedure TViewBase.SetRememberEventProc(aValue: TRememberEventProc);
begin
  FRememberEventProc := aValue;
end;

function TViewBase.GetView: TComponent;
begin
  Result := FView;
end;

function TViewBase.GetOnRecover: TViewRecoverProc;
begin
  Result := FOnRecover;
end;

procedure TViewBase.SetOnRecover(aValue: TViewRecoverProc);
begin
  FOnRecover := aValue;
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

function TModelIO.GetModelClassType: TClass;
begin
  Result := FModelClassType;
end;

function TModelIO.GetObject(const aIndex: Integer): TObject;
begin
  Result := FObjects.Items[aIndex];
end;

constructor TModelIO.Create(aModelClassType: TClass);
begin
  inherited Create;

  FModelClassType := aModelClassType;
end;

{TModelsHelper}

procedure TModelsHelper.Add(aModel: IModel; aModelClass: TModelClass; const aIndex: Integer; aTask: ITask);
var
  ModelItem: TModelItem;
begin
  ModelItem.Model := aModel;
  ModelItem.ModelClass := aModelClass;
  ModelItem.Index := aIndex;
  ModelItem.Task := aTask;

  Self := Self + [ModelItem];
end;

function TModelsHelper.GetTasks: TArray<ITask>;
var
  ModelItem: TModelItem;
begin
  Result := [];

  for ModelItem in Self do
    Result := Result + [ModelItem.Task];
end;

procedure TModelsHelper.Remove(aModelClass: TClass);
var
  i: Integer;
begin
  for i := 0 to Length(Self) - 1 do
    if Self[i].ModelClass = aModelClass then
    begin
      Delete(Self, i, 1);
      Exit;
    end;
end;

procedure TModelsHelper.CancelAll;
var
  ModelItem: TModelItem;
begin
  for ModelItem in Self do
    ModelItem.Model.Cancel;
end;

initialization
  gAllowDirectConstructorForView := False;

end.

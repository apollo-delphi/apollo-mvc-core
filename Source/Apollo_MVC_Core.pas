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
  TModelEventProc = procedure(const aEventName: string; aOutput: IModelIO) of object;
  TViewEventProc = procedure(const aEventName: string; aView: TObject) of object;
  TRememberEventProc = procedure(aView: TObject; const aPropName: string; const aValue: Variant) of object;

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
    procedure CheckCancel;
    procedure FireEvent(const aEventName: string; aOutput: IModelIO);
    procedure OnCancel; virtual;
    procedure Start; virtual; abstract;
  public
    constructor CreateByController(aInput: IModelIO; aModelEventProc: TModelEventProc);
    destructor Destroy; override;
  end;

  TModelClass = class of TModelAbstract;

  IViewBase = interface
  ['{DFCD4E01-FA56-4205-98A2-5CA0980651BB}']
    function GetEventProc: TViewEventProc;
    function GetRememberEventProc: TRememberEventProc;
    procedure FireEvent(const aEventName: string);
    procedure Remember(const aPropName: string; const aValue: Variant);
    procedure SetEventProc(aValue: TViewEventProc);
    procedure SetRememberEventProc(aValue: TRememberEventProc);
    property EventProc: TViewEventProc read GetEventProc write SetEventProc;
    property RememberEventProc: TRememberEventProc read GetRememberEventProc write SetRememberEventProc;
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
    FModels: TArray<TModelItem>;
    FObjectStorage: TObjectDictionary<string, TObject>;
    procedure ViewClose(aView: TComponent);
  protected
    FViews: TObjectDictionary<TClass, TComponent>;
    function ExtractFromStorage<T: class>(const aKey: string): T;
    function GetFromStorage<T: class>(const aKey: string): T;
    function NewInput: IModelIO;
    function TryGetFromStorage<T: class>(const aKey: string; out aValue: T): Boolean;
    function TryGetModel<T: TModelAbstract>(out aModel: IModel; const aIndex: Integer = 0): Boolean;
    function TryGetView<T: TComponent>(out aView: T): Boolean;
    procedure AfterCreate; virtual;
    procedure BeforeDestroy; virtual;
    procedure CallModel<T: TModelAbstract, constructor>(aInput: IModelIO; aThreadCount: Integer = 1); overload;
    procedure CallModel<T: TModelAbstract, constructor>(aThreadCount: Integer = 1); overload;
    procedure RemoveFromStorage(const aKey: string); overload;
    procedure RemoveFromStorage(aValue: TObject); overload;
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
  System.SysUtils;

type
  TViewBase = class(TInterfacedObject, IViewBase)
  private
    FEventProc: TViewEventProc;
    FRememberEventProc: TRememberEventProc;
    FView: TObject;
    function GetEventProc: TViewEventProc;
    function GetRememberEventProc: TRememberEventProc;
    procedure FireEvent(const aEventName: string);
    procedure Remember(const aPropName: string; const aValue: Variant);
    procedure SetEventProc(aValue: TViewEventProc);
    procedure SetRememberEventProc(aValue: TRememberEventProc);
  public
    constructor Create(aView: TObject);
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

function MakeViewBase(aOwner: TObject): IViewBase;
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

destructor TModelAbstract.Destroy;
begin
  FEventProc('ModelDestroy', NewOutput);

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
  Value: TComponent;
begin
  Result := FViews.TryGetValue(T, Value);
  if Result then
    aView := Value as T;
end;

procedure TControllerAbstract.ModelEventsObserver(const aEventName: string;
  aOutput: IModelIO);
var
  ModelEventHandleProc: TModelEventHandleProc;
begin
  if aEventName = 'ModelDestroy' then
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

function TControllerAbstract.NewInput: IModelIO;
begin
  Result := TModelIO.Create(nil);
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
  if aEventName = 'ViewClose' then
  begin
    ViewClose(aView as TComponent);
    Exit;
  end;

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

procedure TControllerAbstract.RemoveFromStorage(const aKey: string);
begin
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
  Result := FObjectStorage.TryGetValue(aKey, Value);
  if Result then
    aValue := Value as T;
end;

procedure TControllerAbstract.ViewClose(aView: TComponent);
begin
  FViews.Remove(aView.ClassType);
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

procedure TViewBase.Remember(const aPropName: string; const aValue: Variant);
begin
  if Assigned(FRememberEventProc) then
    FRememberEventProc(FView, aPropName, aValue);
end;

function TViewBase.GetRememberEventProc: TRememberEventProc;
begin
  Result := FRememberEventProc;
end;

procedure TViewBase.SetRememberEventProc(aValue: TRememberEventProc);
begin
  FRememberEventProc := aValue;
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

end.

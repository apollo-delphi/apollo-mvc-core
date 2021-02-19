unit Apollo_MVC_Core;

interface

uses
  System.Classes,
  System.Generics.Collections;

type
  IModelOutput = interface
  ['{BC1D1100-7593-4AAF-BADE-68902C480EA2}']
    function AddObject(const aIndex: Integer; aObject: TObject): IModelOutput;
    function GetObject(const aIndex: Integer): TObject;
  end;

  TControllerAbstract = class;
  TModelEventProc = procedure(const aEventName: string; aOutput: IModelOutput) of object;
  TViewEventProc = procedure(const aEventName: string; aView: TObject) of object;

  IModel = interface
  ['{37C50BE9-755C-4827-871A-9F812F7169E8}']
    procedure Start;
  end;

  TModelAbstract = class abstract(TInterfacedObject, IModel)
  private
    FEventProc: TModelEventProc;
  protected
    function NewOutput: IModelOutput;
    procedure FireEvent(const aEventName: string; aOutput: IModelOutput);
    procedure Start; virtual; abstract;
  public
    constructor CreateByController(aModelEventProc: TModelEventProc);
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
    procedure AfterCreate; virtual;
    procedure BeforeDestroy; virtual;
    procedure CallModel<T: TModelAbstract, constructor>(aThreadCount: Integer = 1);
    procedure PutToStorage(const aKey: string; aObject: TObject);
  public
    procedure ModelEventsObserver(const aEventName: string; aOutput: IModelOutput);
    procedure ViewEventsObserver(const aEventName: string; aView: TObject);
    constructor Create;
    destructor Destroy; override;
  end;

implementation

uses
  System.SysUtils,
  System.Threading;

type
  TModelEventHandleProc = procedure(aOutput: IModelOutput) of object;
  TViewEventHandleProc = procedure(aView: TObject) of object;

  TModelOutput = class(TInterfacedObject, IModelOutput)
  strict private
    FObjects: TObjectDictionary<Integer, TObject>;
    function AddObject(const aIndex: Integer; aObject: TObject): IModelOutput;
    function GetObject(const aIndex: Integer): TObject;
    procedure AfterConstruction; override;
    procedure BeforeDestruction; override;
  end;

{ TModelAbstract }

constructor TModelAbstract.CreateByController(aModelEventProc: TModelEventProc);
begin
  FEventProc := aModelEventProc;
end;

procedure TModelAbstract.FireEvent(const aEventName: string; aOutput: IModelOutput);
begin
  FEventProc(aEventName, aOutput);
end;

function TModelAbstract.NewOutput: IModelOutput;
begin
  Result := TModelOutput.Create;
end;

{ TControllerAbstract }

procedure TControllerAbstract.AfterCreate;
begin
end;

procedure TControllerAbstract.BeforeDestroy;
begin
end;

procedure TControllerAbstract.CallModel<T>(aThreadCount: Integer = 1);
var
  i: Integer;
  Model: IModel;
  Task: ITask;
begin
  for i := 0 to aThreadCount - 1 do
  begin
    Model := T.CreateByController(ModelEventsObserver);
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
  aOutput: IModelOutput);
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

{ TModelOutput }

function TModelOutput.AddObject(const aIndex: Integer;
  aObject: TObject): IModelOutput;
begin
  FObjects.Add(aIndex, aObject);
  Result := Self;
end;

procedure TModelOutput.AfterConstruction;
begin
  inherited;

  FObjects := TObjectDictionary<Integer, TObject>.Create;
end;

procedure TModelOutput.BeforeDestruction;
begin
  inherited;

  FObjects.Free;
end;

function TModelOutput.GetObject(const aIndex: Integer): TObject;
begin
  Result := FObjects.Items[aIndex];
end;

end.

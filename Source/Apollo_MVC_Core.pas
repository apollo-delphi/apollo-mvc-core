unit Apollo_MVC_Core;

interface

type
  IController = interface
  ['{27228C42-8BD8-4201-8DAA-798EC0098F63}']
  end;

  TController = class(TInterfacedObject, IController)
  end;

  TControllerClass = class of TController;

  TMVCService = record
    procedure RegisterController(aControllerClass: TControllerClass);
  end;

implementation

{ TMVCService }

procedure TMVCService.RegisterController(aControllerClass: TControllerClass);
begin
end;

end.

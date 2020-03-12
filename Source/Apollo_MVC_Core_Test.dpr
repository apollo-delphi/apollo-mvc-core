program Apollo_MVC_Core_Test;

{$STRONGLINKTYPES ON}
uses
  Vcl.Forms,
  System.SysUtils,
  DUnitX.Loggers.GUI.VCL,
  DUnitX.Loggers.Xml.NUnit,
  DUnitX.TestFramework,
  tst_Apollo_MVC_Core in 'tst_Apollo_MVC_Core.pas',
  Apollo_MVC_Core in 'Apollo_MVC_Core.pas',
  Apollo_HTTP in '..\Vendors\Apollo_HTTP\Source\Apollo_HTTP.pas';

begin
  Application.Initialize;
  Application.Title := 'DUnitX';
  Application.CreateForm(TGUIVCLTestRunner, GUIVCLTestRunner);
  Application.Run;
end.

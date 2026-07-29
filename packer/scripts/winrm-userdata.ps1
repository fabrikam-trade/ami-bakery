<powershell>
# Packer bake-time only: open WinRM for the provisioner connection.
# This user_data is NOT part of the golden image -- infra-terraform's
# launch template supplies its own user_data at instance launch.
Set-ExecutionPolicy Unrestricted -Scope LocalMachine -Force -ErrorAction Ignore
winrm quickconfig -q
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="1024"}'
netsh advfirewall firewall add rule name="WinRM 5985" protocol=TCP dir=in localport=5985 action=allow
net stop winrm
sc.exe config winrm start= auto
net start winrm
</powershell>

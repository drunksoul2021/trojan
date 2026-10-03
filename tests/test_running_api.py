#!/usr/bin/env python3
import re,os,base64,json,urllib.request,urllib.parse,urllib.error
from concurrent.futures import ThreadPoolExecutor
BASE='http://127.0.0.1:80'
def api(path,method='GET',data=None,token=None):
    body=urllib.parse.urlencode(data).encode() if data is not None else None
    headers={'Authorization':'Bearer '+token} if token else {}
    request=urllib.request.Request(BASE+path,data=body,headers=headers,method=method)
    with urllib.request.urlopen(request,timeout=10) as response: return json.load(response)

def main():
    token=api('/auth/login','POST',{'username':os.getenv('TROJAN_TEST_ADMIN_USER','smoke-admin'),'password':'test-admin-password-123'})['token']
    assert api('/auth/loginUser',token=token)['data']['isAdmin'] is True
    with ThreadPoolExecutor(max_workers=8) as pool:
        results=list(pool.map(lambda _: api('/auth/loginUser',token=token)['data']['isAdmin'],range(24)))
    assert all(results), 'Concurrent requests lost administrator role'
    users=api('/trojan/user',token=token)['Data']['userList']; assert users
    try: api('/auth/login','POST',{'username':'admin','password':'test-admin-password-123'})
    except urllib.error.HTTPError as e: assert e.code==401
    else: raise AssertionError('Default admin alias unexpectedly still accepted')
    try: api('/auth/register','POST',{'username':'admin','password':'attacker-password-123'})
    except urllib.error.HTTPError as e: assert e.code==403
    else: raise AssertionError('Administrator overwrite was allowed')
    username="test'quoted"
    if not any(u['Username']==username for u in users):
        assert api('/trojan/user','POST',{'username':username,'password':base64.b64encode(b'user-password-123').decode()},token)['Msg']=='success'
    user_token=api('/auth/login','POST',{'username':username,'password':'user-password-123'})['token']
    assert api('/auth/loginUser',token=user_token)['data']['isAdmin'] is False
    scoped=api('/trojan/user',token=user_token)['Data']['userList']; assert len(scoped)==1 and scoped[0]['Username']==username
    try: api('/trojan/user/page',token=user_token)
    except urllib.error.HTTPError as e: assert e.code==403
    else: raise AssertionError('Normal user accessed administrator API')
    with urllib.request.urlopen(BASE+'/') as response: html=response.read().decode()
    assert 'id="app"' in html
    assert not re.search(r'(src|href)="https?://',html), 'Management page requires external CDN'
    script=re.search(r'src="([^"]+\.js)"',html).group(1)
    with urllib.request.urlopen(urllib.parse.urljoin(BASE+'/',script)) as response: assert len(response.read())>1000
    users=api('/trojan/user',token=token)['Data']['userList']
    assert len(users)==2, 'User data was lost or duplicated'
    print('API_INTEGRATION_OK: login, quoted user, authorization, embedded webpage, preserved users')
if __name__=='__main__': main()

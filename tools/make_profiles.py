# Run on the box AFTER the App Group is assigned to both bundle IDs in developer.apple.com.
# Creates App Store profiles via ASC API and stores them as GitHub secrets (never printed).
import subprocess, base64
exec(open('/home/box/.secrets/asc.py').read().split("B='https://api.appstoreconnect.apple.com/v1/'")[0]+"B='https://api.appstoreconnect.apple.com/v1/'")
cert=[c['id'] for c in requests.get(B+'certificates',headers=H).json()['data'] if c['attributes']['certificateType'] in ('DISTRIBUTION','IOS_DISTRIBUTION')][0]
for bid,name,sec in [('com.limuye.everysecondpays','EverySecondPays AppStore CI','APP_PROFILE'),('com.limuye.everysecondpays.widget','EverySecondPays Widget AppStore CI','WIDGET_PROFILE')]:
    for p in requests.get(B+'profiles',headers=H,params={'filter[name]':name}).json()['data']: requests.delete(B+'profiles/'+p['id'],headers=H)
    b=[x for x in requests.get(B+'bundleIds',headers=H,params={'filter[identifier]':bid}).json()['data'] if x['attributes']['identifier']==bid][0]['id']
    r=requests.post(B+'profiles',headers=H,json={'data':{'type':'profiles','attributes':{'name':name,'profileType':'IOS_APP_STORE'},'relationships':{'bundleId':{'data':{'type':'bundleIds','id':b}},'certificates':{'data':[{'type':'certificates','id':cert}]}}}})
    print(name,r.status_code)
    subprocess.run(['gh','secret','set',sec,'-R','limuye0501-dev/EverySecondPays'],input=r.json()['data']['attributes']['profileContent'].encode(),check=True)

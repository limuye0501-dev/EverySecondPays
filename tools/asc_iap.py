import hashlib, os, json
exec(open('/home/box/.secrets/asc.py').read().split("B='https://api.appstoreconnect.apple.com/v1/'")[0])
V1='https://api.appstoreconnect.apple.com/v1/'; V2='https://api.appstoreconnect.apple.com/v2/'
APP='6830853796'; SHOT='/workspace/niuma/iap_review.png'
P=[('com.limuye.everysecondpays.pro','Pro Lifetime','NON_CONSUMABLE','1.99',True,
    {'zh-Hans':('每秒都在赚 Pro','永久解锁全部音效、小组件、皮肤和统计'),'en-US':('Every Second Pays Pro','Unlock all sounds, widgets, skins and stats')}),
   ('com.limuye.everysecondpays.tip.small','Tip Small','CONSUMABLE','0.99',False,
    {'zh-Hans':('一枚铜钱','给小猪喂个元宝，解锁元宝猪皮肤'),'en-US':('Copper Coin','A small tip; unlocks the Ingot Piggy skin')}),
   ('com.limuye.everysecondpays.tip.medium','Tip Medium','CONSUMABLE','2.99',False,
    {'zh-Hans':('一锭银子','给小猪喂个元宝，解锁元宝猪皮肤'),'en-US':('Silver Ingot','A kind tip; unlocks the Ingot Piggy skin')}),
   ('com.limuye.everysecondpays.tip.large','Tip Large','CONSUMABLE','4.99',False,
    {'zh-Hans':('一个大元宝','给小猪喂个大元宝，解锁元宝猪皮肤'),'en-US':('Gold Ingot','A big tip; unlocks the Ingot Piggy skin')})]
def ok(r,what):
    print(what, r.status_code, '' if r.ok else r.text[:300].replace('\n',' ')); return r
existing={x['attributes']['productId']:x['id'] for x in requests.get(V1+f'apps/{APP}/inAppPurchasesV2',headers=H,params={'limit':50}).json().get('data',[])}
terr=[t['id'] for t in requests.get(V1+'territories',headers=H,params={'limit':200}).json()['data']]
for pid,ref,typ,usd,fam,loc in P:
    if pid in existing: iid=existing[pid]; print('exists',pid)
    else:
        a={'name':ref,'productId':pid,'inAppPurchaseType':typ,'reviewNote':'Unlocks features shown on the paywall (Settings > Unlock Pro). Tips unlock a bonus skin. No account needed.'}
        if fam: a['familySharable']=True
        r=ok(requests.post(V2+'inAppPurchases',headers=H,json={'data':{'type':'inAppPurchases','attributes':a,'relationships':{'app':{'data':{'type':'apps','id':APP}}}}}),'create '+pid)
        iid=r.json()['data']['id']
    have={l['attributes']['locale'] for l in requests.get(V2+f'inAppPurchases/{iid}/inAppPurchaseLocalizations',headers=H).json().get('data',[])}
    for lc,(n,dsc) in loc.items():
        if lc not in have:
            ok(requests.post(V1+'inAppPurchaseLocalizations',headers=H,json={'data':{'type':'inAppPurchaseLocalizations','attributes':{'locale':lc,'name':n,'description':dsc},'relationships':{'inAppPurchaseV2':{'data':{'type':'inAppPurchases','id':iid}}}}}),f' loc {lc}')
    pp=requests.get(V2+f'inAppPurchases/{iid}/pricePoints',headers=H,params={'filter[territory]':'USA','limit':800}).json()['data']
    pt=[x for x in pp if x['attributes']['customerPrice']==usd][0]['id']
    ok(requests.post(V1+'inAppPurchasePriceSchedules',headers=H,json={'data':{'type':'inAppPurchasePriceSchedules','relationships':{
        'inAppPurchase':{'data':{'type':'inAppPurchases','id':iid}},'baseTerritory':{'data':{'type':'territories','id':'USA'}},
        'manualPrices':{'data':[{'type':'inAppPurchasePrices','id':'${p0}'}]}}},
        'included':[{'type':'inAppPurchasePrices','id':'${p0}','attributes':{'startDate':None},'relationships':{'inAppPurchasePricePoint':{'data':{'type':'inAppPurchasePricePoints','id':pt}}}}]}),f' price ${usd}')
    ok(requests.post(V1+'inAppPurchaseAvailabilities',headers=H,json={'data':{'type':'inAppPurchaseAvailabilities','attributes':{'availableInNewTerritories':True},'relationships':{
        'inAppPurchase':{'data':{'type':'inAppPurchases','id':iid}},'availableTerritories':{'data':[{'type':'territories','id':t} for t in terr]}}}}),f' availability {len(terr)}')
    cur=requests.get(V2+f'inAppPurchases/{iid}/appStoreReviewScreenshot',headers=H).json().get('data')
    if not cur:
        b=open(SHOT,'rb').read()
        r=ok(requests.post(V1+'inAppPurchaseAppStoreReviewScreenshots',headers=H,json={'data':{'type':'inAppPurchaseAppStoreReviewScreenshots','attributes':{'fileName':'review.png','fileSize':len(b)},'relationships':{'inAppPurchaseV2':{'data':{'type':'inAppPurchases','id':iid}}}}}),' shot reserve')
        d=r.json()['data']
        for op in d['attributes']['uploadOperations']:
            requests.request(op['method'],op['url'],headers={h['name']:h['value'] for h in op['requestHeaders']},data=b[op['offset']:op['offset']+op['length']])
        ok(requests.patch(V1+'inAppPurchaseAppStoreReviewScreenshots/'+d['id'],headers=H,json={'data':{'type':'inAppPurchaseAppStoreReviewScreenshots','id':d['id'],'attributes':{'uploaded':True,'sourceFileChecksum':hashlib.md5(b).hexdigest()}}}),' shot commit')
    st=requests.get(V2+f'inAppPurchases/{iid}',headers=H).json()['data']['attributes']['state']; print(' state',st)

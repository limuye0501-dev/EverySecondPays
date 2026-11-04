# Cuts real CC0 Freesound recordings (previews in /workspace/niuma/sounds/src) into soft <1s coin drops.
import numpy as np, scipy.signal as sg, scipy.io.wavfile as w, subprocess, os
SR=44100; SRC='/workspace/niuma/sounds/src'; OUT='/workspace/niuma/app/EverySecondPays/Resources/Sounds'
def load(id):
    raw=subprocess.run(['ffmpeg','-loglevel','error','-i',f'{SRC}/{id}.mp3','-ac','1','-ar',str(SR),'-f','f32le','-'],capture_output=True).stdout
    return np.frombuffer(raw,np.float32).astype(float)
def events(x):
    e=np.sqrt(sg.convolve(x**2,np.ones(441)/441,'same')); thr=e.max()*0.25
    on=np.where((e[1:]>thr)&(e[:-1]<=thr))[0]; out=[]
    for o in on:
        if not out or o-out[-1]>int(.8*SR): out.append(o)
    return out, e
def cut(id,pick):
    x=load(id); on,e=events(x)
    # prefer isolated events: quiet for 0.25s before
    iso=[o for o in on if e[max(0,o-int(.3*SR)):o-int(.05*SR)].max(initial=0)<e[o:o+2000].max()*0.2] or on
    o=iso[min(pick,len(iso)-1)]; s=max(0,o-int(.015*SR)); return x[s:s+int(.9*SR)], len(on), o/SR
def finish(name,x,fc=5500):
    x=sg.sosfilt(sg.butter(2,fc,'low',fs=SR,output='sos'),x)
    x=sg.sosfilt(sg.butter(2,80,'high',fs=SR,output='sos'),x)
    x=np.tanh(2.5*x/np.abs(x).max())  # soften sharp transients
    k=int(.006*SR); x[:k]*=np.linspace(0,1,k)
    k=int(.25*SR); x[-k:]*=np.cos(np.linspace(0,np.pi/2,k))**2
    x*=10**(-38/20)/np.sqrt(np.mean(x**2))
    if np.abs(x).max()>10**(-18/20): x*=10**(-18/20)/np.abs(x).max()
    os.makedirs(OUT,exist_ok=True); p=f'{OUT}/{name}.wav'; w.write(p,SR,(x*32767).astype(np.int16))
    subprocess.run(['ffmpeg','-y','-loglevel','error','-i',p,'-b:a','192k',f'/workspace/niuma/sounds/v2_{name}.mp3'])
    F,P=sg.welch(x,SR,nperseg=2048)
    print(f'{name:16s} rms {20*np.log10(np.sqrt(np.mean(x**2))):.1f} dBFS  >6k {100*P[F>6000].sum()/P.sum():.2f}%  centroid {np.sum(F*P)/P.sum():.0f}Hz')
plan={'empty_pig':('536075',0,5500),'coin_pile':('400116',0,4000),'ceramic_pig':('560194',0,3800),'glass_bowl':('190031',1,4500),'penny_slot':('173877',2,5500)}
for n,(id,pk,fc) in plan.items():
    seg,cnt,t=cut(id,pk); print(n,id,'events',cnt,'at',round(t,2)); finish(n,seg,fc)

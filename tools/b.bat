@echo off  
echo import sys > h.py  
echo from PIL import Image >> h.py  
echo src=sys.argv[1] >> h.py  
echo im=Image.open(src).convert('RGBA') >> h.py  
echo W,H=im.size >> h.py  
echo pix=im.load() >> h.py  
echo for y in range(H): >> h.py  
echo     cnt=sum(1 for x in range(W) if pix[x,y][3]^>8) >> h.py  
echo     if cnt^>0: print((y,cnt),flush=True) >> h.py  

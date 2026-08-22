import sys  
from PIL import Image  
src=sys.argv[1]  
im=Image.open(src).convert('RGBA')  
W,H=im.size  
pix=im.load()  
for y in range(H):  
    cnt=sum(1 for x in range(W) if pix[x,y][3] 
    if cnt print((y,cnt),flush=True)  

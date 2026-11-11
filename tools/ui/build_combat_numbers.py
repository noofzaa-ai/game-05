"""Bake the approved outlined digit treatment into one small shared RGBA atlas."""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'art/ui/combat_numbers';OUT.mkdir(parents=True,exist_ok=True)
font=ImageFont.truetype(str(ROOT/'art_source/fonts/changa-one/ChangaOne-Italic.ttf'),72)
chars='0123456789+.'
size=(80,112)
atlas=Image.new('RGBA',(1024,512))
palettes=[((255,255,255),(229,225,216)),((255,211,83),(255,102,8)),((190,255,174),(19,218,92)),((255,160,151),(239,47,47))]
advances=[]
for row,(top,bottom) in enumerate(palettes):
 for col,ch in enumerate(chars):
  glyph=Image.new('RGBA',size)
  mask=Image.new('L',size);d=ImageDraw.Draw(mask)
  d.text((12,12),ch,font=font,fill=255,stroke_width=0)
  outline=Image.new('L',size);ImageDraw.Draw(outline).text((12,12),ch,font=font,fill=255,stroke_width=5)
  shadow=Image.new('L',size);ImageDraw.Draw(shadow).text((12,18),ch,font=font,fill=255,stroke_width=6)
  glyph.alpha_composite(Image.composite(Image.new('RGBA',size,(18,11,9,255)),Image.new('RGBA',size),shadow))
  glyph.alpha_composite(Image.composite(Image.new('RGBA',size,(47,27,20,255)),Image.new('RGBA',size),outline))
  gradient=Image.new('RGBA',size);gd=ImageDraw.Draw(gradient)
  for y in range(size[1]):
   t=max(0,min(1,(y-28)/54));c=tuple(round(a+(b-a)*t) for a,b in zip(top,bottom))
   gd.line((0,y,size[0],y),fill=(*c,255))
  glyph.alpha_composite(Image.composite(gradient,Image.new('RGBA',size),mask))
  atlas.alpha_composite(glyph,(col*80,row*112))
  if row==0:advances.append(round(font.getlength(ch))+1)
atlas.save(OUT/'digits.png',optimize=True)
(OUT/'digits.json').write_text(json.dumps({'characters':chars,'advances':advances,'cell':[80,112],'rows':['normal','critical','heal','incoming']},indent=2)+'\n')
print('Atlas:',(OUT/'digits.png').stat().st_size,'bytes')

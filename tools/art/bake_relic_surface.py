"""Read-only high-mesh BVH projection into new textures; never exports or saves Blender geometry."""
import bpy,json,math,time
import numpy as np
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[2];work=ROOT/'art_source/props/goblin_base/rebake1000';out=ROOT/'art/relics/goblin/baked';out.mkdir(exist_ok=True)
# Input texels as linear colours; Blender handles PNG sRGB IO, data maps remain non-colour.
def read(name,data=False):
 im=bpy.data.images.load(str(ROOT/'art_source/props/goblin_base/shared'/name),check_existing=False)
 if data:im.colorspace_settings.name='Non-Color'
 a=np.empty(im.size[0]*im.size[1]*4,dtype=np.float32);im.pixels.foreach_get(a);a=a.reshape(im.size[1],im.size[0],4);return a
colour=read('relic_colour.png');normalmap=read('relic_normal.png',True);mr=read('relic_mr.png',True)
def sample(a,uv):
 # glTF v-down, image pixel array bottom-up.
 x=min(a.shape[1]-1,max(0,int(uv[0]*a.shape[1])));y=min(a.shape[0]-1,max(0,int((1-uv[1])*a.shape[0])))
 return a[y,x,:3]
def unit(v):return v/max(float(np.linalg.norm(v)),1e-12)
for name in ['goblin_medallion','goblin_lantern']:
 d=json.loads((work/(name+'.json')).read_text());src=d['source'];verts=src['POSITION'];faces=d['source_indices'];tree=BVHTree.FromPolygons([Vector(v) for v in verts],faces,all_triangles=True)
 sv=np.array(verts);sn=np.array(src['NORMAL']);st=np.array(src['TANGENT']);su=np.array(src['TEXCOORD_0']);fi=np.array(faces);s_tri=sv[fi];p=np.array(d['positions']);n=np.array(d['normals']);tan=np.array(d['tangents']);target=np.zeros((512,512,4),dtype=np.float32);nt=np.zeros_like(target);mt=np.zeros_like(target)
 for i in range(len(p)//3):
  tri=p[i*3:i*3+3];tn=n[i*3];tt=tan[i*3,:3];tb=np.cross(tn,tt)*tan[i*3,3];cx,cy=i%32,i//32
  for y in range(16):
   for x in range(16):
    u=(x+.5-1.5)/13;v=(y+.5-1.5)/13
    # Gutter extrapolation clamped onto the face instead of black/transparent padding.
    u=max(0,u);v=max(0,v)
    if u+v>1:u,v=u/(u+v),v/(u+v)
    point=tri[0]*(1-u-v)+tri[1]*u+tri[2]*v
    hit,hn,face,dist=tree.find_nearest(Vector(point))
    a,b,c=s_tri[face];e0=b-a;e1=c-a;e2=np.array(hit)-a;d00=np.dot(e0,e0);d01=np.dot(e0,e1);d11=np.dot(e1,e1);den=d00*d11-d01*d01
    if abs(den)<1e-20:w=np.array([1.,0,0])
    else:
     b1=(d11*np.dot(e2,e0)-d01*np.dot(e2,e1))/den;b2=(d00*np.dot(e2,e1)-d01*np.dot(e2,e0))/den;w=np.array([1-b1-b2,b1,b2]);w=np.maximum(w,0);w/=sum(w)
    ids=fi[face];uv=(su[ids]*w[:,None]).sum(0);norm=unit((sn[ids]*w[:,None]).sum(0));tangent=unit((st[ids,:3]*w[:,None]).sum(0));bitangent=np.cross(norm,tangent)*(1 if (st[ids,3]*w).sum()>0 else -1)
    mapped=sample(normalmap,uv)*2-1;world=unit(tangent*mapped[0]+bitangent*mapped[1]+norm*mapped[2]);baked_normal=unit(np.array([np.dot(world,tt),np.dot(world,tb),np.dot(world,tn)]))*.5+.5
    # Target UV y-down; output pixels bottom-up.
    yy=511-(cy*16+y);xx=cx*16+x
    target[yy,xx]=[*sample(colour,uv),1];nt[yy,xx]=[*baked_normal,1];mt[yy,xx]=[*sample(mr,uv),1]
  if i%200==0:print(name,i,'/',len(p)//3,flush=True)
 for role,values,size in [('colour',target,512),('normal',nt,256),('mr',mt,256)]:
  # Save numeric texels directly; Blender PNG save applies a display transform to float buffers.
  np.save(str(work/(name+'_'+role+'.npy')),values[:,:,:3])
 print('BAKED',name,flush=True)

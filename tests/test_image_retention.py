import importlib.util,time,unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('retention',Path(__file__).resolve().parents[1]/'tools/backend/image_retention.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class Retention(unittest.TestCase):
 def setUp(self):
  self.now=time.time();self.policy=dict(repositories=['zorx-web'],registry_aliases=['wiyazard:30500','192.168.1.74:30500'],keep_latest=3,minimum_age_days=14,keep_tag_patterns=['stable'])
  self.rows=[dict(repository='zorx-web',tag=str(i),digest='sha256:'+str(i)*64,media_type=next(iter(m.SINGLE)),created=self.now-(20+i)*86400) for i in range(5)]
 def test_latest_and_old(self):
  result=m.plan(self.rows,set(),self.policy,self.now);self.assertEqual([r['reason'] for r in result].count('expired'),2)
 def test_running_alias_digest(self):
  refs={'192.168.1.74:30500/zorx-web@'+self.rows[4]['digest']};self.assertNotEqual(m.plan(self.rows,refs,self.policy,self.now)[4]['reason'],'expired')
 def test_shared_digest_kept_by_tag(self):
  self.rows.append({**self.rows[4],'tag':'stable'});self.assertNotEqual(m.plan(self.rows,set(),self.policy,self.now)[4]['reason'],'expired')
 def test_unknown_media_or_age_never_deleted(self):
  self.rows[4]['media_type']='index';self.rows[3]['created']=None
  result=m.plan(self.rows,set(),self.policy,self.now)
  self.assertTrue(all(result[i]['reason']!='expired' for i in [3,4]))
 def test_live_and_replica_images_collected(self):
  self.assertEqual(m.workload_refs({'items':[{'spec':{'containers':[{'image':'a'}]}},{'status':{'containerStatuses':[{'imageID':'docker-pullable://b@sha256:x'}]}}]}),{'a','b@sha256:x'})

 def test_unknown_age_does_not_consume_latest_slots(self):
  self.rows.extend([{**self.rows[4], 'tag':'unknown'+str(i),'digest':'sha256:unknown'+str(i),'created':None} for i in range(5)])
  result=m.plan(self.rows,set(),self.policy,self.now)
  self.assertTrue(all(result[i]['reason']!='expired' for i in range(3)))

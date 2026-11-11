"""Bounded aggregate origin budgets; deliberately not based on spoofable forwarded IPs."""
from pathlib import Path
import yaml

def resources():
    def middleware(name, spec):
        return dict(apiVersion='traefik.io/v1alpha1',kind='Middleware',metadata=dict(name=name,namespace='zorx-staging'),spec=spec)
    return [middleware('origin-budget',{'rateLimit':{'average':100,'burst':200,'sourceCriterion':{'requestHost':True}}}),
            middleware('room-admission-budget',{'rateLimit':{'average':4,'burst':8,'sourceCriterion':{'requestHost':True}}}),
            middleware('origin-buffer',{'buffering':{'maxRequestBodyBytes':65536,'memRequestBodyBytes':65536}})]

if __name__=='__main__':
    Path(__file__).with_name('security.yaml').write_text(yaml.safe_dump_all(resources(),sort_keys=False))

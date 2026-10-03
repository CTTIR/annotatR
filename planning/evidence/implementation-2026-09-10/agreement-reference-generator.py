"""Independent exact-fraction agreement oracle over literal row-major arrays."""
from collections import Counter
from fractions import Fraction
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parent

def ratio(num, den):
    return None if not den else {'fraction': str(Fraction(num, den)), 'value': num / den}

def compare(a, b, codes, bitfield=False):
    aa = sum(a, []); bb = sum(b, [])
    assert len(aa) == len(bb)
    rows = []
    for value, label in codes:
        ma = [bool(x & value) if bitfield else x == value for x in aa]
        mb = [bool(x & value) if bitfield else x == value for x in bb]
        tp = sum(x and y for x, y in zip(ma, mb))
        fp = sum(not x and y for x, y in zip(ma, mb))
        fn = sum(x and not y for x, y in zip(ma, mb))
        rows.append(dict(value=value, label=label, n_true=sum(ma), n_pred=sum(mb),
                         tp=tp, fp=fp, fn=fn, dice=ratio(2*tp, 2*tp+fp+fn),
                         iou=ratio(tp, tp+fp+fn)))
    out = dict(reference=a, prediction=b, n_px=len(aa), per_class=rows)
    if bitfield:
        out['exact_membership_set_agreement'] = ratio(sum(x==y for x,y in zip(aa,bb)),len(aa))
        out['categorical_kappa'] = 'not defined here: bitfield codes are sets, not mutually exclusive classes'
    else:
        cats = sorted(set(aa + bb))
        confusion = [[sum(x==r and y==c for x,y in zip(aa,bb)) for c in cats] for r in cats]
        n = len(aa); po = Fraction(sum(x==y for x,y in zip(aa,bb)),n)
        ca, cb = Counter(aa), Counter(bb)
        pe = sum((Fraction(ca[c]*cb[c], n*n) for c in cats),Fraction(0))
        out.update(confusion_codes=cats,confusion=confusion,
                   accuracy=ratio(po.numerator,po.denominator),
                   chance_agreement=ratio(pe.numerator,pe.denominator),
                   kappa=None if pe==1 else ratio(((po-pe)/(1-pe)).numerator,((po-pe)/(1-pe)).denominator))
    return out

a=[[0,1,1,2],[0,1,2,2],[0,0,2,1]]
b=[[0,1,2,2],[0,1,2,0],[1,0,2,1]]
bit_a=[[0,1,3,2],[1,3,0,2],[0,0,2,1]]
bit_b=[[0,1,1,2],[3,3,0,0],[0,2,2,1]]
result={
 'convention':'Each input is an explicit row-major list. Cells are paired directly; no rasterizer or package reader is used.',
 'absent_class_policy':'A zero union has undefined Dice/IoU represented as null; macro policy must state whether this class is excluded.',
 'categorical':compare(a,b,[(1,'A'),(2,'B'),(3,'absent')]),
 'remapped_prediction':{'matrix':[[{0:0,1:2,2:1}[x] for x in row] for row in b],
                        'codebook':{'0':'background','2':'A','1':'B','3':'absent'},
                        'expected_after_explicit_by_label_alignment':'same as categorical case'},
 'bitfield':compare(bit_a,bit_b,[(1,'A'),(2,'B'),(4,'absent')],True),
 'background_only':{'matrix':[[0,0],[0,0]],'accuracy':1,'chance_agreement':1,
                    'kappa':None,'reason':'Kappa denominator 1-pe is zero; reporting 1 would claim an undefined statistic.'}
}
(ROOT/'expected.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
assert result['categorical']['accuracy']['fraction']=='3/4'
assert result['categorical']['kappa']['fraction']=='5/8'
assert result['categorical']['confusion']==[[3,1,0],[0,3,1],[1,0,3]]
print('Independent agreement oracle: exact categorical accuracy 3/4, kappa 5/8; literal bitfield and absent-class counts generated.')

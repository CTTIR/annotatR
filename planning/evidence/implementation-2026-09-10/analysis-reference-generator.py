from pathlib import Path
import json
import numpy as np

out = Path(__file__).parent
cube = np.fromfunction(lambda y, x, b: 100*(b+1) + 10*(y+1) + x+1, (4,5,3), dtype=float)
cube[0,0,0] = np.nan
cube[1,2,1] = np.inf
cube[2,3,2] = -np.inf
cube[3,4,2] = np.nan
masks = {'A': np.zeros((4,5), dtype=bool), 'B': np.zeros((4,5), dtype=bool)}
masks['A'][0:3,0:3] = True
masks['B'][1:4,2:5] = True
bitfield = masks['A'].astype('i4') + 2*masks['B'].astype('i4')
rows = []
for name, mask in masks.items():
    for b in range(3):
        samples = cube[:,:,b][mask]
        finite = samples[np.isfinite(samples)]
        rows.append(dict(roi=name, band=b+1, wavelength_nm=[450,550,650][b],
                         n_selected=int(samples.size), n_valid=int(finite.size),
                         n_invalid=int(samples.size-finite.size),
                         mean=float(np.mean(finite)), median=float(np.median(finite)),
                         sd=float(np.std(finite, ddof=1)), min=float(np.min(finite)),
                         max=float(np.max(finite)), sum=float(np.sum(finite))))
result = dict(shape_yxb=list(cube.shape), invalid_samples_zero_based=[
    [0,0,0,'NaN'],[1,2,1,'+Inf'],[2,3,2,'-Inf'],[3,4,2,'NaN']],
    roi_cells_zero_based={'A':'y=0..2,x=0..2','B':'y=1..3,x=2..4'},
    bitfield=bitfield.tolist(), n_foreground=int(np.count_nonzero(bitfield)),
    n_overlap=int(np.count_nonzero(bitfield == 3)), n_background=int(np.count_nonzero(bitfield == 0)),
    finite_omit_statistics=rows)
# Distinct estimands: a unique-pixel union vs repeated ROI memberships.
union = masks['A'] | masks['B']
union_rows = []
for b in range(3):
    selected = cube[:, :, b][union]
    finite = selected[np.isfinite(selected)]
    union_rows.append(dict(band=b+1, wavelength_nm=[450,550,650][b],
                           n_selected=int(selected.size), n_valid=int(finite.size),
                           n_invalid=int(selected.size-finite.size),
                           mean=float(np.mean(finite)), median=float(np.median(finite)),
                           sd=float(np.std(finite, ddof=1)), min=float(np.min(finite)),
                           max=float(np.max(finite)), sum=float(np.sum(finite))))
result['union_pixel_statistics'] = union_rows
result['sampling_units'] = dict(unique_selected_pixels=16, selected_roi_memberships=18,
                               roi_count=2, image_count=1,
                               note='ROI membership totals count the two overlapping cells twice; a unique-pixel image summary does not.')
cube.astype('<f4').tofile(out/'cube.dat')
(out/'cube.hdr').write_text('ENVI\nsamples = 5\nlines = 4\nbands = 3\nheader offset = 0\ndata type = 4\ninterleave = bip\nbyte order = 0\nwavelength = {450, 550, 650}\nwavelength units = nm\n')
np.save(out/'cube.npy', cube, allow_pickle=False)
(out/'expected.json').write_text(json.dumps(result, indent=2, allow_nan=False)+'\n')
print(json.dumps({'shape': list(cube.shape), 'selected_each': [int(m.sum()) for m in masks.values()],
                  'foreground': result['n_foreground'], 'overlap': result['n_overlap'], 'background': result['n_background']}))

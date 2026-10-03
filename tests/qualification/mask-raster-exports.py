"""Independent output qualification: tifffile and stdlib PNG scanline decoding.
Usage: python3 tests/qualification/mask-raster-exports.py OUTPUT_DIRECTORY
The R generator exports 32 small synthetic arrays via normal/optional writers.
"""
import hashlib, json, pathlib, struct, sys, zlib
import imagecodecs, numpy, tifffile
root = pathlib.Path(sys.argv[1])

def png_decode(path):
    blob = path.read_bytes()
    assert blob[:8] == b'\x89PNG\r\n\x1a\n'
    pos, data = 8, b''
    while pos < len(blob):
        count = struct.unpack('>I', blob[pos:pos+4])[0]
        kind, payload = blob[pos+4:pos+8], blob[pos+8:pos+8+count]
        assert zlib.crc32(kind+payload) == struct.unpack('>I',blob[pos+8+count:pos+12+count])[0]
        if kind == b'IHDR':
            width,height,depth,colour,compression,filtering,interlace = struct.unpack('>IIBBBBB',payload)
            assert colour == 0 and depth in (8,16) and compression == filtering == interlace == 0
        if kind == b'IDAT': data += payload
        pos += count+12
    raw = zlib.decompress(data)
    bpp, stride = depth//8, width*(depth//8)
    previous = [0]*stride
    rows = []
    assert len(raw)==height*(stride+1)
    for y in range(height):
        offset=y*(stride+1)
        filt=raw[offset]
        row=list(raw[offset+1:offset+stride+1])
        for x in range(stride):
            a=row[x-bpp] if x>=bpp else 0
            b=previous[x]
            c=previous[x-bpp] if x>=bpp else 0
            p=a+b-c
            distances=[abs(p-a),abs(p-b),abs(p-c)]
            paeth=[a,b,c][distances.index(min(distances))]
            row[x]=(row[x]+[0,a,b,(a+b)//2,paeth][filt])%256
        rows.append(list(struct.unpack('>'+('B' if depth==8 else 'H')*width,bytes(row))))
        previous=row
    return depth,rows

results=[]
for path in sorted(root.glob('*.*')):
    if path.suffix not in ('.tiff','.png'): continue
    mode, bits, name = path.stem.split('-'); bits=int(bits)
    expected={'zero':[[0,0,0],[0,0,0]],'binary':[[0,1,0],[1,0,1]],
              'extrema':[[0,2**bits-1,0],[2**bits-1,0,2**bits-1]],
              'codes':[[0,1,255,256],[4096,32767,32768,65535]] if bits==16 else [[0,1,9,10],[13,32,128,255]]}[name]
    if path.suffix=='.png':
        depth,rows=png_decode(path)
        dtype=f'uint{depth}'
    else:
        with tifffile.TiffFile(path) as tif:
            assert len(tif.pages)==1
            page=tif.pages[0]
            depth=page.bitspersample
            dtype=str(page.dtype)
            assert page.samplesperpixel==1
            rows=page.asarray().tolist()
    assert depth==bits and dtype==f'uint{bits}', (path.name,depth,dtype)
    assert rows==expected, (path.name,rows,expected)
    results.append(dict(file=path.name,bits=depth,dtype=dtype,rows=rows,sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
assert len(results)==32
print(json.dumps(dict(status='PASS',files=len(results),python=sys.version.split()[0],numpy=numpy.__version__,tifffile=tifffile.__version__,imagecodecs=imagecodecs.__version__,results=results),indent=2))

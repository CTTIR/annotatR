from pathlib import Path
import struct
p=Path(__file__).resolve().parent
(p/'reference.pgm').write_bytes(b'P5\n4 2\n65535\n'+struct.pack('>8H',0,1,255,256,4096,32767,32768,65535))
for bits in [8,16]:
    for name,vals in [('zeros',[0,0]),('binary',[0,1]),('extremes',[0,2**bits-1])]:
        (p/f'{name}{bits}.pgm').write_bytes(f'P5\n2 1\n{2**bits-1}\n'.encode()+struct.pack('>2'+('B' if bits==8 else 'H'),*vals))

import 'dart:io';
import 'dart:typed_data';
import 'package:flu_doom/engine/wad/wad.dart';
void main(){
  final b = File('assets/doom1.wad').readAsBytesSync();
  final w = WadFile.fromBytes(Uint8List.fromList(b));
  print('numLumps=${w.numLumps} id=${w.identification}');
  for (final n in ['E1M1','TEXTURE1','TEXTURE2','F_START','F_END','S_START','S_END','PNAMES']) {
    print('$n -> ${w.lumpNumForName(n)}');
  }
  final e = w.lumpNumForName('E1M1');
  for (int i=e;i<e+11;i++){ print('  [$i] ${w.lumpByIndex(i).name} size=${w.lumpByIndex(i).size}'); }
}

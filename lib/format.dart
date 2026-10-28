/// Taille lisible par un humain : « 45,2 Mo », « 812 ko », « 3,1 Go ».
String formatBytes(int bytes) {
  if (bytes <= 0) return 'taille inconnue';
  const units = ['o', 'ko', 'Mo', 'Go'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = unit == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1).replaceAll('.', ',');
  return '$text ${units[unit]}';
}

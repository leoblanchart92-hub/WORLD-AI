/// Version applicative au format `majeur.mineur.correctif`.
///
/// La lecture est tolérante : `1.2.3`, `v1.2.3`, `1.2.3+12`, `1.2` et
/// `1.2.3-rc.1` (suffixe de pré-version ignoré) sont acceptés.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);

  factory AppVersion.parse(String raw) {
    var value = raw.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1);
    }
    // Métadonnées de build (1.2.3+4) et pré-version (1.2.3-rc.1) ignorées.
    value = value.split('+').first.split('-').first;

    final parts = value.split('.');
    final major = int.tryParse(parts.first.trim());
    if (major == null) {
      throw FormatException('Version illisible : "$raw"');
    }
    int part(int index) =>
        index < parts.length ? (int.tryParse(parts[index].trim()) ?? 0) : 0;

    return AppVersion(major, part(1), part(2));
  }

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;
  bool operator <(AppVersion other) => compareTo(other) < 0;
  bool operator >=(AppVersion other) => compareTo(other) >= 0;
  bool operator <=(AppVersion other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) => other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

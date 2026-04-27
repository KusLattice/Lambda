/// Regiones de Chile y sus comunas principales.
/// Fuente de verdad única para filtros de Hospedaje, Picás, y futuros módulos.
const Map<String, List<String>> kChileRegions = {
  'Arica y Parinacota': ['Arica', 'Camarones', 'Putre', 'General Lagos'],
  'Tarapacá': ['Iquique', 'Alto Hospicio', 'Pozo Almonte', 'Pica', 'Huara'],
  'Antofagasta': [
    'Antofagasta',
    'Mejillones',
    'Calama',
    'San Pedro de Atacama',
    'Tocopilla',
    'Taltal',
  ],
  'Atacama': ['Copiapó', 'Caldera', 'Vallenar', 'Chañaral', 'Diego de Almagro'],
  'Coquimbo': [
    'La Serena',
    'Coquimbo',
    'Ovalle',
    'Illapel',
    'Vicuña',
    'Andacollo',
  ],
  'Valparaíso': [
    'Valparaíso',
    'Viña del Mar',
    'Quilpué',
    'Villa Alemana',
    'San Antonio',
    'Quillota',
    'Los Andes',
    'San Felipe',
  ],
  'Metropolitana': [
    'Santiago',
    'Puente Alto',
    'Maipú',
    'La Florida',
    'Las Condes',
    'Ñuñoa',
    'Providencia',
    'Peñalolén',
    'San Bernardo',
    'Colina',
  ],
  'O\'Higgins': ['Rancagua', 'San Fernando', 'Rengo', 'Machalí', 'Pichilemu'],
  'Maule': ['Talca', 'Curicó', 'Linares', 'Constitución', 'Cauquenes'],
  'Ñuble': ['Chillán', 'San Carlos', 'Bulnes', 'Quirihue'],
  'Biobío': [
    'Concepción',
    'Los Ángeles',
    'Chiguayante',
    'Talcahuano',
    'Coronel',
    'Lota',
    'Tomé',
  ],
  'Araucanía': [
    'Temuco',
    'Padre Las Casas',
    'Villarrica',
    'Pucón',
    'Angol',
    'Victoria',
  ],
  'Los Ríos': ['Valdivia', 'La Unión', 'Panguipulli', 'Río Bueno', 'Corral'],
  'Los Lagos': [
    'Puerto Montt',
    'Osorno',
    'Castro',
    'Puerto Varas',
    'Ancud',
    'Quellón',
    'Calbuco',
  ],
  'Aysén': ['Coyhaique', 'Puerto Aysén', 'Chile Chico', 'Cochrane'],
  'Magallanes': [
    'Punta Arenas',
    'Puerto Natales',
    'Porvenir',
    'Puerto Williams',
  ],
};

/// Lista simple de nombres de regiones, útil para dropdowns.
final List<String> kRegionNames = kChileRegions.keys.toList();

/// Helper para autodetectar la región desde el administrativeArea del GPS
String? matchChileRegion(String? administrativeArea) {
  if (administrativeArea == null || administrativeArea.isEmpty) return null;
  final normalized = administrativeArea.toLowerCase();

  for (final region in kRegionNames) {
    if (normalized.contains(region.toLowerCase())) return region;
  }

  // Fallbacks for common variations
  if (normalized.contains('santiago') || normalized.contains('metropolitana')) return 'Metropolitana';
  if (normalized.contains('o\'higgins') || normalized.contains('ohiggins') || normalized.contains('libertador')) return 'O\'Higgins';
  if (normalized.contains('biobio') || normalized.contains('bío bío') || normalized.contains('biobío')) return 'Biobío';
  if (normalized.contains('araucania') || normalized.contains('araucanía')) return 'Araucanía';
  if (normalized.contains('tarapaca') || normalized.contains('tarapacá')) return 'Tarapacá';
  if (normalized.contains('valparaiso') || normalized.contains('valparaíso')) return 'Valparaíso';
  if (normalized.contains('nuble') || normalized.contains('ñuble')) return 'Ñuble';
  if (normalized.contains('rios') || normalized.contains('ríos')) return 'Los Ríos';
  if (normalized.contains('lagos')) return 'Los Lagos';
  if (normalized.contains('aysen') || normalized.contains('aysén')) return 'Aysén';
  if (normalized.contains('magallanes') || normalized.contains('antartica') || normalized.contains('antártica')) return 'Magallanes';

  return null;
}

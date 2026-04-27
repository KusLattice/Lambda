const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

// 1. Validar que exista serviceAccountKey.json
const serviceAccountPath = path.join(__dirname, 'serviceAccountKey.json');
if (!fs.existsSync(serviceAccountPath)) {
  console.error("❌ ERROR: No se encontró 'serviceAccountKey.json'.");
  console.error("Ve a Configuración del Proyecto > Cuentas de Servicio en Firebase y genera una nueva clave privada. Guárdala aquí con ese nombre.");
  process.exit(1);
}

const serviceAccount = require(serviceAccountPath);

// Inicializar Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  storageBucket: 'lambda-c242a.firebasestorage.app'
});

const bucket = admin.storage().bucket();
const db = admin.firestore();

async function run() {
  console.log('🚀 Iniciando Despliegue Automático Lambda OTA (Node.js)...');

  // 2. Leer pubspec.yaml
  const pubspecPath = path.join(__dirname, '../../pubspec.yaml');
  if (!fs.existsSync(pubspecPath)) {
    console.error('❌ ERROR: No se encontró pubspec.yaml en la raíz del proyecto.');
    process.exit(1);
  }

  const pubspecFile = fs.readFileSync(pubspecPath, 'utf8');
  const pubspecData = yaml.load(pubspecFile);
  
  if (!pubspecData.version) {
    console.error('❌ ERROR: No se encontró la etiqueta "version" en pubspec.yaml.');
    process.exit(1);
  }

  const versionParts = pubspecData.version.split('+');
  const version = versionParts[0];
  const buildNumber = parseInt(versionParts[1], 10);

  const vMajorMinorPatch = version.split('.');
  const major = vMajorMinorPatch[0] || '0';
  const minor = vMajorMinorPatch[1] || '0';
  const patch = parseInt(vMajorMinorPatch[2] || '0', 10);

  let greek = 'α';
  if (patch === 1) greek = 'β';
  if (patch === 2) greek = 'γ';
  if (patch >= 3)  greek = 'λ';

  const displayVersion = `v${major}.${minor}${greek}`;

  console.log(`📦 Detectada Versión: ${version} (Build ${buildNumber}) -> Mostrará: ${displayVersion}`);

  // 3. Localizar APK
  let apkPath = path.join(__dirname, '../../build/app/outputs/flutter-apk/app-release.apk');
  const altApkPath = path.join(__dirname, '../../lambda_v0.2_beta.apk'); // en caso de que esté en la raíz

  if (!fs.existsSync(apkPath)) {
    if (fs.existsSync(altApkPath)) {
      apkPath = altApkPath;
    } else {
      console.error(`❌ ERROR: No se encontró el APK en ${apkPath}`);
      console.error('Corre "flutter build apk --release" primero.');
      process.exit(1);
    }
  }

  console.log(`📍 Usando APK: ${apkPath}`);

  const localOutput = path.join(__dirname, `../../lambda_app_${displayVersion}.apk`);
  try {
    fs.copyFileSync(apkPath, localOutput);
    console.log(`✅ APK copiado localmente como: lambda_app_${displayVersion}.apk`);
  } catch (e) {
    console.log(`⚠️ No se pudo copiar localmente (quizás está en uso): ${e.message}`);
  }

  // 4. Subir APK a Firebase Storage
  const destinationPath = `updates/lambda_app_${displayVersion}.apk`;
  console.log(`☁️ Subiendo APK a Storage (${destinationPath})... esto puede tomar unos minutos.`);

  try {
    // Si da error "The specified bucket does not exist", tu Firebase Storage
    // tal vez use otro formato, ej. usando directamente el storage default 
    // pero generalmente lambda-c242a.appspot.com es correcto.
    await bucket.upload(apkPath, {
      destination: destinationPath,
      metadata: {
        contentType: 'application/vnd.android.package-archive',
        metadata: {
          version: version,
          buildNumber: buildNumber.toString()
        }
      }
    });
    
    // Hacer público el archivo temporalmente (o depender de las reglas públicas en gs)
    // Usaremos la URL pública directa
    console.log('✅ APK subido exitosamente.');

    // URL pública aproximada
    const downloadUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(destinationPath)}?alt=media`;
    console.log(`🔗 URL de descarga: ${downloadUrl}`);

    // 5. Actualizar Firestore
    console.log('🔥 Actualizando metadatos en Firestore...');

    const args = process.argv.slice(2);
    const updateNotes = args.length > 0 ? args.join(' ') : 'Mejoras de estabilidad y mística técnica introducidas por el co-dev de Seba.';

    const appInfoRef = db.collection('metadata').doc('app_info');
    await appInfoRef.set({
      latest_version: version,
      display_version: displayVersion,
      latest_build_number: buildNumber,
      apk_download_url: downloadUrl,
      update_notes: updateNotes,
      is_mandatory: false,
      updated_at: admin.firestore.FieldValue.serverTimestamp()
    });

    console.log('\n🎯 DESPLIEGUE COMPLETADO CON ÉXITO.');
    console.log(`La versión ${version} (Build ${buildNumber}) ya está lista para que se actualice sola en los dispositivos.`);

  } catch (error) {
    console.error('❌ ERROR DURANTE EL DESPLIEGUE:', error);
  } finally {
    process.exit(0); // Cerrar para liberar procesos de Firebase
  }
}

run();

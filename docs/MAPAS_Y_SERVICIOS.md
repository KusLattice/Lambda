# Mapas y servicios necesarios para Lambda App

Guía para enlazar el mapa y los servicios de Google que usa la app en un entorno serio/producción.

---

## 1. Qué usa la app hoy

| Plataforma | Implementación | API / servicio |
|------------|----------------|-----------------|
| **Windows** | WebView con iframe | **Maps Embed API** (vista + búsqueda por lugar) |
| **Android** | `google_maps_flutter` nativo | **Maps SDK for Android** |
| **iOS** | `google_maps_flutter` nativo | **Maps SDK for iOS** |
| **Web** (si la usas) | `google_maps_flutter_web` | **Maps JavaScript API** |

Todas usan la misma **API key de Google Maps Platform**. Opcionalmente puedes añadir **Geocoding API** para que en móvil la búsqueda por dirección funcione de verdad (hoy en móvil solo mueve a una posición fija).

---

## 2. Pasos en Google Cloud (obligatorios)

### 2.1 Proyecto y facturación

1. Entra a [Google Cloud Console](https://console.cloud.google.com/).
2. Usa el mismo proyecto que ya tienes para Firebase (p. ej. `lambda-c242a`) o crea uno solo para la app.
3. **Activa la facturación** en ese proyecto (Google Maps requiere cuenta de facturación; hay crédito gratuito mensual que suele bastar para desarrollo y poco tráfico).

### 2.2 Activar las APIs necesarias

En **APIs y servicios → Biblioteca** activa:

- **Maps Embed API** (para Windows/WebView con iframe).
- **Maps SDK for Android** (para Android).
- **Maps SDK for iOS** (para iOS).
- **Maps JavaScript API** (solo si vas a compilar para web y usar el mapa en web).

Opcional (búsqueda por dirección en móvil):

- **Geocoding API**.

### 2.3 Crear o usar una API key

1. **APIs y servicios → Credenciales**.
2. **+ Crear credenciales → Clave de API**.
3. Copia la clave (la usarás en los pasos siguientes).

### 2.4 Restringir la clave (recomendado en serio)

Para no dejarla abierta a todo el mundo:

1. En la clave recién creada → **Restringir clave**.
2. **Restricciones de aplicación**:
   - **Android**: agregar el nombre del paquete `com.example.lambda_app` y la huella SHA-1 de tu keystore (debug y release).
   - **iOS**: agregar el ID del bundle (p. ej. `com.example.lambdaApp`).
   - **Referentes HTTP** (para Embed/Web): agregar los dominios donde correrá la app (p. ej. `localhost`, tu dominio de producción, `*.google.com` para el iframe si lo pide la doc).
3. **Restricciones de API**: limitar a las que uses:
   - Maps Embed API  
   - Maps SDK for Android  
   - Maps SDK for iOS  
   - Maps JavaScript API (solo si usas web)  
   - Geocoding API (solo si la activaste)

Así la clave solo sirve para tu app y para esas APIs.

---

## 3. Dónde configurar la API key en el proyecto

### 3.1 Android

La app lee la clave desde **`android/local.properties`** (este archivo está en `.gitignore` y no se sube a Git).

1. Copia el ejemplo: `cp android/local.properties.example android/local.properties`
2. Edita `android/local.properties` y reemplaza `TU_GOOGLE_MAPS_API_KEY` por tu clave.
3. Ajusta `sdk.dir` y `flutter.sdk` a las rutas de tu máquina si hace falta.

El `AndroidManifest.xml` usa `android:value="${maps.apiKey}"` y `build.gradle.kts` inyecta el valor desde `local.properties`.

### 3.2 iOS

La clave se inyecta en **build time** desde un xcconfig y se lee en **`ios/Runner/Info.plist`** como `$(MAPS_API_KEY)`. El `AppDelegate` la toma del `Bundle` (ya no está hardcodeada).

1. Copia el ejemplo: `cp ios/Flutter/Config.xcconfig.example ios/Flutter/Config.xcconfig`
2. Edita **`ios/Flutter/Config.xcconfig`** y pon tu clave: `MAPS_API_KEY=tu_key`.
3. El archivo `Config.xcconfig` está en `.gitignore`; no se sube a Git.

Si no creas `Config.xcconfig`, se usará el valor por defecto `REPLACE_ME` y el mapa no cargará hasta que configures la clave.

### 3.3 Windows (y clave en Dart/Flutter)

En Windows el mapa usa un **WebView** con **Maps Embed API**. La clave se lee en **`lib/config/app_config.dart`** (getter que usa `String.fromEnvironment`).

- **Desarrollo**: se usa la clave por defecto definida en `AppConfig.defaultMapsApiKey` (solo para pruebas locales).
- **Producción**: inyecta la clave en build time y no la subas al repo:

```bash
flutter run -d windows --dart-define=MAPS_API_KEY=tu_key
flutter build windows --dart-define=MAPS_API_KEY=tu_key
```

### 3.4 Web (si usas web)

Para **Maps JavaScript API** en web necesitas la clave en el HTML que carga el script de Google Maps (por ejemplo en `web/index.html`). La documentación de `google_maps_flutter_web` indica cómo pasar la API key; suele ser un parámetro en la URL del script. Usa la misma clave restringida por “Referentes HTTP” a tu dominio.

---

## 4. Resumen de “qué necesito para que funcione”

| Qué | Dónde / Cómo |
|-----|----------------|
| Proyecto Google Cloud con facturación | Console → mismo proyecto que Firebase (o uno dedicado) |
| APIs activadas | Maps Embed, Maps SDK Android, Maps SDK iOS; opcional: Geocoding, Maps JavaScript (web) |
| Una API key | Credenciales → Crear clave de API |
| Restricciones de la clave | Por plataforma (Android/iOS/HTTP) y por API |
| Android | `android/local.properties` → `maps.apiKey=...` |
| iOS | `ios/Runner/AppDelegate.swift` → `GMSServices.provideAPIKey("...")` |
| Windows / Dart | `AppConfig.mapsApiKey` o `--dart-define=MAPS_API_KEY=...` |
| Web (si aplica) | Clave en `web/index.html` (o donde cargues el script de Maps) |

---

## 5. Búsqueda por dirección en Android/iOS (Geocoding)

La app ya usa **Geocoding API** en móvil: al escribir una dirección y buscar, se llama a la API, se obtienen lat/lng y se mueve la cámara a esa posición.

Para que funcione:

1. En Google Cloud Console activa **Geocoding API** (APIs y servicios → Biblioteca).
2. En la restricción de tu API key, permite **Geocoding API** (o usa la misma clave que para Maps).

La clave se toma de la misma configuración que el mapa (Android: `local.properties`; iOS: `Config.xcconfig`; en Dart se usa `AppConfig.mapsApiKey`).

---

## 6. Enlaces útiles

- [Google Maps Platform – Get started](https://developers.google.com/maps/documentation/android-sdk/start)
- [Maps Embed API](https://developers.google.com/maps/documentation/embed/get-started)
- [Restringir API keys](https://cloud.google.com/docs/authentication/api-keys#restrict_key)
- [Créditos y precios Maps](https://developers.google.com/maps/billing-and-pricing)

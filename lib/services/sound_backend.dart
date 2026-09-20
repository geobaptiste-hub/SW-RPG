// Backend audio multiplateforme (fix web 20/09).
//
//  - WEB : `dart:html` AudioElement direct — audioplayers_web 4.x route
//    le son via un AudioContext WebAudio créé HORS geste utilisateur,
//    qui reste suspendu (politique autoplay Safari/Chrome) et n'est
//    jamais repris → silence total. Les éléments <audio> simples ne
//    souffrent pas de ce problème.
//  - DESKTOP : audioplayers (inchangé).
export 'sound_backend_io.dart'
    if (dart.library.html) 'sound_backend_web.dart';

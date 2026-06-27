import Toybox.Lang;

// Paleta dotmesh. Fuente de verdad: dotmesh/docs/DESIGN.md (Paper · Ink · Syntax).
// Sobre Ink se usan los pasteles de sintaxis directamente; el color es señal,
// nunca decoración. Si cambias un color, cámbialo primero en DESIGN.md.
module Palette {
    // Ink — superficies oscuras
    const INK_0    = 0x16171B; // lienzo base
    const INK_1    = 0x1C1D22; // panel elevado

    // Texto sobre Ink
    const PAPER    = 0xE9EAEC; // primario
    const TEXT_2   = 0x9A9DA4; // secundario
    const TEXT_DIM = 0x6A6D74; // atenuado / comentarios

    // Syntax — los siete acentos (significado entre paréntesis)
    const PEACH    = 0xFFAA7A; // números, constantes → Claude (notificaciones)
    const LILAC    = 0xCBAACB; // palabras clave
    const TEAL     = 0x6CB6B0; // especial, cursor (lo vivo)
    const BLUE     = 0x8FB4E3; // funciones → pasos
    const SAGE     = 0xA8CBA0; // cadenas; correcto → chevron del prompt
    const GOLD     = 0xE3C58A; // tipos
    const ROSE     = 0xE59A9A; // errores → batería baja

    // Chrome — rampa de grafito para la powerline (espejo de DESIGN.md → Chrome).
    // Cuatro escalones (chrome-2..5), cada vez más claros, para leer las costuras.
    const CHROME_2  = 0x383838; // notificaciones
    const CHROME_3  = 0x424242; // batería
    const CHROME_4  = 0x4D4D4D; // fecha
    const CHROME_5  = 0x545454; // pasos
    const CHROME_TX = 0xEAEAEA; // texto sobre los segmentos

    // En always-on (AOD) el fondo es negro puro: ahorra batería en AMOLED y
    // reduce el burn-in. La hora del modo activo es blanco puro (hero); en AOD
    // se atenúa. Versiones atenuadas locales a la esfera (la voz AOD no existe
    // en las otras superficies del lenguaje).
    const AOD_TIME   = 0x7A7A7A; // hora atenuada
    const AOD_CHEV   = 0x4D5A58; // chevron sage atenuado
    const AOD_CURSOR = 0x37514E; // cursor teal atenuado
    const AOD_DATE   = 0x3F3F3F; // fecha casi apagada
}

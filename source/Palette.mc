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
    const PEACH    = 0xFFAA7A; // números, constantes
    const LILAC    = 0xCBAACB; // palabras clave
    const TEAL     = 0x6CB6B0; // especial, cursor (lo vivo)
    const BLUE     = 0x8FB4E3; // funciones
    const SAGE     = 0xA8CBA0; // cadenas; correcto
    const GOLD     = 0xE3C58A; // tipos
    const ROSE     = 0xE59A9A; // errores

    // En always-on (AOD) el fondo es negro puro: ahorra batería en AMOLED
    // y reduce el riesgo de burn-in frente al Ink-0.
    const AOD_BG   = 0x000000;
}

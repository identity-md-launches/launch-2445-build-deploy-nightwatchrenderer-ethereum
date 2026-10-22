// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface INightFrogsRenderer {
    function traitSVG(uint8 layer, uint8 index) external view returns (string memory);
}

interface IArtStore {
    function read(uint256 index) external view returns (string memory);
}

/// @title NightWatchRenderer
/// @notice Stateless NIGHT WATCHERS SVG composition using the existing Ethereum artwork.
/// @dev The label and dependency strings are inserted verbatim, as specified. Callers
///      displaying untrusted labels must isolate SVG content. No token or metadata state
///      is maintained here. All dependency calls are STATICCALLs.
contract NightWatchRenderer {
    INightFrogsRenderer private constant FROGS = INightFrogsRenderer(0x4D9BfbafE31eC18E9D3066F1475e24906d155D67);
    IArtStore private constant ART = IArtStore(0x2A0140BC2b117ffEe9b092af1a927b96328FB000);

    error InvalidTier(uint8 tier);

    /// @notice Render one watcher. Everyone may call; only tiers 1 through 6 are valid.
    /// @param n Watcher number (including zero for the supplied Captain vector).
    /// @param t Tier, where 6 is The Captain.
    /// @param traits NIGHT FROGS trait indices for layers 0 through 6.
    /// @param label Literal label; no XML escaping or normalization is performed.
    /// @param inputs Ten source frog numbers, displayed in their supplied order.
    /// @param points Forge points displayed on the plate.
    function svg(
        uint256 n,
        uint8 t,
        uint8[7] calldata traits,
        string calldata label,
        uint16[10] calldata inputs,
        uint16 points
    ) external view returns (string memory) {
        if (t < 1 || t > 6) revert InvalidTier(t);
        string memory color = _color(t);
        string memory number = _decimal(n);
        string memory roman = _roman(t);

        string memory background = string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" width="1000" height="1000" color="',
            color,
            '"><title>NIGHT WATCHERS #',
            number,
            "</title>",
            ART.read(0),
            _defs(color),
            FROGS.traitSVG(0, traits[0]),
            _light(t),
            _raysAndRings(t)
        );

        string memory subject = string.concat(
            '<g filter="url(#otA)">',
            FROGS.traitSVG(1, traits[1]),
            FROGS.traitSVG(2, traits[2]),
            FROGS.traitSVG(3, traits[3]),
            t >= 3 ? '<g filter="url(#otE)">' : "",
            FROGS.traitSVG(4, traits[4]),
            t >= 3 ? "</g>" : "",
            FROGS.traitSVG(5, traits[5]),
            FROGS.traitSVG(6, traits[6]),
            "</g>"
        );

        return string.concat(
            background,
            subject,
            traits[6] == 1
                ? string.concat(
                    '<text x="500" y="858" font-size="23" fill="#08070D" text-anchor="middle">NW', number, "</text>"
                )
                : "",
            t == 6 ? ART.read(3) : "",
            t >= 3 ? _embers(t) : "",
            t >= 4
                ? '<rect x="-500" y="0" width="2000" height="1000" fill="url(#otH)" opacity=".45" style="mix-blend-mode:overlay"><animateTransform attributeName="transform" type="translate" values="-1000 0;1000 0" dur="6s" repeatCount="indefinite"/></rect>'
                : "",
            _frame(t),
            _titleAndPips(t),
            _hexAndSpine(t, roman),
            _plate(number, label, inputs, points),
            "</svg>"
        );
    }

    function _color(uint8 t) private pure returns (string memory) {
        if (t == 1) return "#3FE6FF";
        if (t == 2) return "#B8FF4A";
        if (t == 3) return "#A98BFF";
        if (t == 4) return "#FF4FD8";
        if (t == 5) return "#FFC46B";
        return "#E9E4FF";
    }

    function _roman(uint8 t) private pure returns (string memory) {
        if (t == 1) return "I";
        if (t == 2) return "II";
        if (t == 3) return "III";
        if (t == 4) return "IV";
        if (t == 5) return "V";
        return "C";
    }

    function _defs(string memory color) private pure returns (string memory) {
        return string.concat(
            '<defs><radialGradient id="otL"><stop offset="0" stop-color="currentColor" stop-opacity=".6"/><stop offset="1" stop-color="currentColor" stop-opacity="0"/></radialGradient><radialGradient id="otR"><stop offset=".15" stop-color="#FFFFFF"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient><mask id="otM"><rect x="0" y="0" width="1000" height="1000" fill="url(#otR)"/></mask><linearGradient id="otH" x1="0" y1="0" x2="1" y2="1"><stop offset=".4" stop-color="#FFFFFF" stop-opacity="0"/><stop offset=".5" stop-color="#FFFFFF" stop-opacity=".7"/><stop offset=".6" stop-color="#FFFFFF" stop-opacity="0"/></linearGradient><filter id="otA" x="-20%" y="-20%" width="140%" height="140%"><feMorphology in="SourceAlpha" operator="dilate" radius="5"/><feGaussianBlur stdDeviation="15" result="b"/><feFlood flood-color="',
            color,
            '"/><feComposite in2="b" operator="in"/><feMerge><feMergeNode/><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter><filter id="otE" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur in="SourceAlpha" stdDeviation="9" result="b"/><feFlood flood-color="',
            color,
            '"/><feComposite in2="b" operator="in"/><feMerge><feMergeNode/><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs>'
        );
    }

    function _light(uint8 t) private pure returns (string memory) {
        string memory opacity = t == 1 ? ".6" : t == 2 ? ".7" : t == 3 ? ".8" : t == 4 ? ".9" : "1";
        return string.concat('<circle cx="500" cy="540" r="480" fill="url(#otL)" opacity="', opacity, '"/>');
    }

    function _spin(string memory to, string memory duration) private pure returns (string memory) {
        return string.concat(
            '<animateTransform attributeName="transform" type="rotate" from="0 500 540" to="',
            to,
            ' 500 540" dur="',
            duration,
            's" repeatCount="indefinite"/>'
        );
    }

    function _raysAndRings(uint8 t) private pure returns (string memory result) {
        if (t >= 2) {
            result = string.concat(
                '<circle cx="500" cy="540" r="330" fill="none" stroke="currentColor" stroke-width="660" stroke-dasharray="8 44" opacity="',
                t <= 3 ? ".22" : ".34",
                '" mask="url(#otM)">',
                t >= 5 ? _spin("360", "80") : "",
                "</circle>"
            );
        }
        if (t >= 3) {
            result = string.concat(
                result,
                '<circle cx="500" cy="540" r="402" fill="none" stroke="currentColor" stroke-width="4" stroke-dasharray="2 16" opacity=".7">',
                t >= 5 ? _spin("360", "120") : "",
                "</circle>"
            );
        }
        if (t >= 5) {
            result = string.concat(
                result,
                '<circle cx="500" cy="540" r="432" fill="none" stroke="currentColor" stroke-width="2" stroke-dasharray="40 14 4 14" opacity=".8">',
                _spin("-360", "90"),
                "</circle>"
            );
        }
    }

    function _embers(uint8 t) private pure returns (string memory result) {
        result = '<g filter="url(#otE)">';
        // The inclusive range 0 .. 4t-7 contains 4t-6 circles (6, 10, 14, 18).
        uint256 count = 4 * uint256(t) - 6;
        for (uint256 k; k < count; ++k) {
            uint256 offset = (37 * k) % 150;
            string memory duration = _decimal(4 + k % 4);
            result = string.concat(
                result,
                '<circle cx="',
                _decimal(k % 2 == 1 ? 890 - offset : 110 + offset),
                '" cy="',
                _decimal(560 + (83 * k) % 340),
                '" r="',
                _decimal(4 + 2 * (k % 3)),
                '" fill="currentColor"><animateTransform attributeName="transform" type="translate" values="0 0;0 -280" dur="',
                duration,
                's" repeatCount="indefinite"/><animate attributeName="opacity" values="0;1;0" dur="',
                duration,
                's" repeatCount="indefinite"/></circle>'
            );
        }
        return string.concat(result, "</g>");
    }

    function _frame(uint8 t) private pure returns (string memory) {
        return string.concat(
            '<rect x="0" y="0" width="1000" height="1000" fill="url(#vignette)"/><rect x="0" y="0" width="1000" height="1000" fill="#FFFFFF" filter="url(#grain)" opacity=".035"/><path d="M60 24H940L976 60V940L940 976H60L24 940V60Z" fill="none" stroke="currentColor" stroke-width="4"/>',
            t >= 2
                ? '<path d="M72 36H928L964 72V928L928 964H72L36 928V72Z" fill="none" stroke="currentColor" stroke-width="1.5" opacity=".45"/><path d="M500 24V44M24 500H44M956 500H976" stroke="currentColor" stroke-width="4"/>'
                : "",
            t >= 4
                ? '<path d="M60 24H940L976 60V940L940 976H60L24 940V60Z" fill="none" stroke="currentColor" stroke-width="12" filter="url(#glow)"><animate attributeName="opacity" values=".15;.7;.15" dur="4s" repeatCount="indefinite"/></path>'
                : "",
            t >= 5
                ? '<path d="M54 10H946L990 54V946L946 990H54L10 946V54Z" fill="none" stroke="currentColor" stroke-width="3"/><path d="M436 44L448 8L476 30L500 2L524 30L552 8L564 44Z" fill="currentColor" stroke="#08070D" stroke-width="4" stroke-linejoin="round"/>'
                : ""
        );
    }

    function _titleAndPips(uint8 t) private pure returns (string memory result) {
        result =
            '<text x="66" y="86" font-size="16" fill="#C4B4FF" letter-spacing="7">NIGHT FROGS / GEN 2</text><text x="62" y="142" font-size="56" fill="#F2EFFF" letter-spacing="5">NIGHT WATCHER</text>';
        for (uint256 k; k < 5; ++k) {
            result = string.concat(
                result,
                '<rect x="',
                _decimal(66 + 34 * k),
                '" y="158" width="26" height="8" fill="currentColor" opacity="',
                k < t ? "1" : ".2",
                '"/>'
            );
        }
    }

    function _hexAndSpine(uint8 t, string memory roman) private pure returns (string memory) {
        return string.concat(
            '<path d="M884 50L936 80V140L884 170L832 140V80Z" fill="',
            t >= 4 ? "currentColor" : "#08070D",
            '" stroke="currentColor" stroke-width="5"/><text x="884" y="126" font-size="',
            t == 3 ? "34" : "40",
            '" fill="',
            t >= 4 ? "#08070D" : "currentColor",
            '" text-anchor="middle">',
            roman,
            '</text><text x="0" y="0" font-size="13" fill="currentColor" letter-spacing="6" text-anchor="middle" opacity=".85" transform="translate(958 520) rotate(90)">NIGHTSHIFT / NIGHT WATCH / TIER ',
            roman,
            "</text>"
        );
    }

    function _plate(string memory number, string calldata label, uint16[10] calldata inputs, uint16 points)
        private
        pure
        returns (string memory)
    {
        string memory from;
        for (uint256 i; i < 10; ++i) {
            from = string.concat(from, i == 0 ? "#" : " #", _decimal(inputs[i]));
        }
        return string.concat(
            '<path d="M64 870H904L940 906L904 942H64Z" fill="#08070D" fill-opacity=".88" stroke="currentColor" stroke-width="3"/><text x="86" y="917" font-size="30" fill="#F2EFFF">#',
            number,
            '</text><text x="',
            _decimal(130 + 20 * bytes(number).length),
            '" y="916" font-size="22" fill="currentColor">',
            label,
            '</text><text x="896" y="916" font-size="18" fill="#C4B4FF" text-anchor="end">',
            _decimal(points),
            ' FP</text><text x="66" y="966" font-size="14" fill="#C4B4FF" letter-spacing="3">FORGED FROM ',
            from,
            "</text>"
        );
    }

    function _decimal(uint256 value) private pure returns (string memory) {
        if (value == 0) return "0";
        uint256 digits = 0;
        uint256 remaining = value;
        while (remaining != 0) {
            ++digits;
            remaining /= 10;
        }
        bytes memory result = new bytes(digits);
        while (value != 0) {
            // 48 + value % 10 is an ASCII decimal digit in [48, 57].
            // forge-lint: disable-next-line(unsafe-typecast)
            result[--digits] = bytes1(uint8(48 + value % 10));
            value /= 10;
        }
        return string(result);
    }
}

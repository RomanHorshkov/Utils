/**
 * @file transforms.h
 * @brief Fast hex/base64 transforms (libsodium-backed) + wipe helper.
 *
 * @author  Roman Horshkov <github.com/RomanHorshkov>
 * @date    2025
 * (c) 2025
 */

#ifndef UTILS_TRANSFORMS_MACROS_H
#define UTILS_TRANSFORMS_MACROS_H

#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include <sodium.h>

#include <emlog.h>


/* default base64 variant for the whole project */
#ifndef SODIUM_B64_VARIANT_DEFAULT
#    define SODIUM_B64_VARIANT_DEFAULT sodium_base64_VARIANT_URLSAFE_NO_PADDING
/* alternatives:
 *  - sodium_base64_VARIANT_ORIGINAL
 *  - sodium_base64_VARIANT_ORIGINAL_NO_PADDING
 *  - sodium_base64_VARIANT_URLSAFE
 *  - sodium_base64_VARIANT_URLSAFE_NO_PADDING
 */
#endif

/* Required output capacity (including terminating NUL) */
#ifndef B64_ENCODED_LEN
#    define B64_ENCODED_LEN(bin_len) \
        sodium_base64_ENCODED_LEN((bin_len), SODIUM_B64_VARIANT_DEFAULT)
#endif

#ifndef HEX_ENCODED_LEN
#    define HEX_ENCODED_LEN(bin_len) ((size_t)(bin_len) * 2u + 1u)
#endif

/* Local zeroize helper */
#ifndef WIPE
#    define WIPE(buf, sz)                       \
        do                                      \
        {                                       \
            sodium_memzero((void*)(buf), (sz)); \
        } while(0)
#endif

/**
 * @brief Hex → bin using libsodium implementation.
 * @note Accepts optional 0x/0X prefix.
 * @return 0 on success; -EINVAL on bad input; -ENOSPC if out_cap too small.
 */
static inline int hex_to_bin_sodium(unsigned char* bin, size_t bin_maxlen, const char* hex,
                                    size_t hex_len, size_t* bin_len)
{
    if(!bin || !hex || !bin_len)
    {
        EML_ERROR("auth_transforms", "hex_to_bin_sodium: invalid inputs");
        return -EINVAL;
    }

    if(hex_len == (size_t)-1) hex_len = strlen(hex);

    if(hex_len >= 2 && hex[0] == '0' && (hex[1] == 'x' || hex[1] == 'X'))
    {
        hex     += 2;
        hex_len -= 2;
    }

    if((hex_len & 1u) != 0u)
    {
        EML_ERROR("auth_transforms", "hex_to_bin_sodium: odd hex length");
        return -EINVAL;
    }

    const size_t need = hex_len / 2u;
    if(need > bin_maxlen)
    {
        EML_ERROR("auth_transforms", "hex_to_bin_sodium: output too small (need %zu)", need);
        return -ENOSPC;
    }

    const char* end = NULL;
    if(sodium_hex2bin(bin, bin_maxlen, hex, hex_len, NULL, bin_len, &end) != 0)
    {
        EML_ERROR("auth_transforms", "hex_to_bin_sodium: sodium_hex2bin failed");
        return -EINVAL;
    }

    if(end != hex + hex_len)
    {
        EML_ERROR("auth_transforms", "hex_to_bin_sodium: partial parse rejected");
        return -EINVAL;
    }

    return 0;
}

/**
 * @brief Bin → base64 using libsodium implementation.
 * @return 0 on success; -EINVAL on bad input; -ENOSPC if out_cap too small.
 */
static inline int bin_to_b64_sodium(char* b64_out, size_t b64_maxlen, const unsigned char* bin,
                                    size_t bin_len, int variant, size_t* b64_len_out)
{
    if(!b64_out || b64_maxlen == 0 || (!bin && bin_len != 0))
    {
        EML_ERROR("auth_transforms", "bin_to_b64_sodium: invalid inputs");
        return -EINVAL;
    }

    const size_t need = sodium_base64_ENCODED_LEN(bin_len, variant);
    if(b64_maxlen < need)
    {
        EML_ERROR("auth_transforms", "bin_to_b64_sodium: output too small (need %zu)", need);
        b64_out[0] = '\0';
        return -ENOSPC;
    }

    if(!sodium_bin2base64(b64_out, b64_maxlen, bin, bin_len, variant))
    {
        EML_ERROR("auth_transforms", "bin_to_b64_sodium: sodium_bin2base64 failed");
        b64_out[0] = '\0';
        return -EIO;
    }

    if(b64_len_out) *b64_len_out = strlen(b64_out);
    return 0;
}

/**
 * @brief Base64 → bin using libsodium implementation (strict; rejects partial parse).
 * @return 0 on success; -EINVAL on invalid base64 or output too small.
 */
static inline int b64_to_bin_sodium(unsigned char* bin, size_t bin_maxlen, const char* b64,
                                    size_t b64_len, int variant, size_t* bin_len_out)
{
    if(!bin || bin_maxlen == 0 || !b64 || !bin_len_out)
    {
        EML_ERROR("auth_transforms", "b64_to_bin_sodium: invalid inputs");
        return -EINVAL;
    }

    if(b64_len == (size_t)-1) b64_len = strlen(b64);

    const char* end = NULL;
    if(sodium_base642bin(bin, bin_maxlen, b64, b64_len, NULL, bin_len_out, &end, variant) != 0)
    {
        EML_ERROR("auth_transforms", "b64_to_bin_sodium: sodium_base642bin failed");
        return -EINVAL;
    }

    if(end != b64 + b64_len)
    {
        EML_ERROR("auth_transforms", "b64_to_bin_sodium: partial parse rejected");
        return -EINVAL;
    }

    return 0;
}

/**
 * @brief Hex → base64 via tmp binary buffer.
 */
static inline int hex_to_b64_sodium(char* b64_out, size_t b64_maxlen, const char* hex,
                                    size_t hex_len, unsigned char* tmp_bin, size_t tmp_maxlen,
                                    int variant, size_t* b64_len_out)
{
    size_t    bin_len = 0;
    const int rc      = hex_to_bin_sodium(tmp_bin, tmp_maxlen, hex, hex_len, &bin_len);
    if(rc != 0)

    {
        EML_ERROR("auth_transforms", "hex_to_b64_sodium: hex_to_bin_sodium failed");
        return rc;
    }
    return bin_to_b64_sodium(b64_out, b64_maxlen, tmp_bin, bin_len, variant, b64_len_out);
}

/**
 * @brief Base64 → hex via tmp binary buffer.
 */
static inline int b64_to_hex_sodium(char* hex_out, size_t hex_maxlen, const char* b64,
                                    size_t b64_len, unsigned char* tmp_bin, size_t tmp_maxlen,
                                    int variant, size_t* hex_len_out)
{
    size_t    bin_len = 0;
    const int rc      = b64_to_bin_sodium(tmp_bin, tmp_maxlen, b64, b64_len, variant, &bin_len);
    if(rc != 0)
    {
        EML_ERROR("auth_transforms", "b64_to_hex_sodium: b64_to_bin_sodium failed");
        return rc;
    }

    const size_t need = HEX_ENCODED_LEN(bin_len);
    if(hex_maxlen < need)
    {
        EML_ERROR("auth_transforms", "b64_to_hex_sodium: output too small (need %zu)", need);
        if(hex_maxlen) hex_out[0] = '\0';
        return -ENOSPC;
    }

    if(!sodium_bin2hex(hex_out, hex_maxlen, tmp_bin, bin_len))
    {
        EML_ERROR("auth_transforms", "b64_to_hex_sodium: sodium_bin2hex failed");
        hex_out[0] = '\0';
        return -EIO;
    }

    if(hex_len_out) *hex_len_out = strlen(hex_out);
    return 0;
}

#ifndef BIN_TO_HEX
#    define BIN_TO_HEX(hex_out, hex_maxlen, bin_in, bin_len)           \
        sodium_bin2hex((char* const)hex_out, (const size_t)hex_maxlen, \
                       (const unsigned char* const)bin_in, (const size_t)bin_len)
#endif

#ifndef HEX_TO_BIN
#    define HEX_TO_BIN(hex, hexlen, bin, binmax, out_lenp)                             \
        hex_to_bin_sodium((unsigned char*)(bin), (size_t)(binmax), (const char*)(hex), \
                          (size_t)(hexlen), (out_lenp))
#endif

#ifndef BIN_TO_B64
#    define BIN_TO_B64(b64_out, b64_maxlen, bin_in, bin_len, out_lenp)                            \
        bin_to_b64_sodium((char*)(b64_out), (size_t)(b64_maxlen), (const unsigned char*)(bin_in), \
                          (size_t)(bin_len), SODIUM_B64_VARIANT_DEFAULT, (out_lenp))
#endif

#ifndef B64_TO_BIN
#    define B64_TO_BIN(b64_in, b64_len, bin_out, bin_maxlen, out_lenp)                            \
        b64_to_bin_sodium((unsigned char*)(bin_out), (size_t)(bin_maxlen), (const char*)(b64_in), \
                          (size_t)(b64_len), SODIUM_B64_VARIANT_DEFAULT, (out_lenp))
#endif

/* Needs a caller-provided temporary buffer for the decoded binary */
#ifndef HEX_TO_B64
#    define HEX_TO_B64(hex_in, hex_len, b64_out, b64_maxlen, tmp_bin, tmp_maxlen, out_b64_lenp) \
        hex_to_b64_sodium((char*)(b64_out), (size_t)(b64_maxlen), (const char*)(hex_in),        \
                          (size_t)(hex_len), (unsigned char*)(tmp_bin), (size_t)(tmp_maxlen),   \
                          SODIUM_B64_VARIANT_DEFAULT, (out_b64_lenp))
#endif

#ifndef B64_TO_HEX
#    define B64_TO_HEX(b64_in, b64_len, hex_out, hex_maxlen, tmp_bin, tmp_maxlen, out_hex_lenp) \
        b64_to_hex_sodium((char*)(hex_out), (size_t)(hex_maxlen), (const char*)(b64_in),        \
                          (size_t)(b64_len), (unsigned char*)(tmp_bin), (size_t)(tmp_maxlen),   \
                          SODIUM_B64_VARIANT_DEFAULT, (out_hex_lenp))
#endif

#endif /* UTILS_TRANSFORMS_MACROS_H */

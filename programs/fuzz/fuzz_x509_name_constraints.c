#include <stdint.h>
#include "mbedtls/x509_crt.h"
#include "psa/crypto.h"
#include "fuzz_common.h"

int LLVMFuzzerTestOneInput(const uint8_t *Data, size_t Size)
{
#ifdef MBEDTLS_X509_CRT_PARSE_C
    mbedtls_x509_crt crt;
    int ret;
#if !defined(MBEDTLS_X509_REMOVE_INFO)
    unsigned char buf[4096];
#endif

    mbedtls_x509_crt_init(&crt);
    if (psa_crypto_init() != PSA_SUCCESS) {
        goto exit;
    }

    /*
     * The X.509 parser validates the nameConstraints extension as part of
     * parsing the certificate. Feeding a complete DER certificate, rather
     * than an isolated extension blob, exercises the surrounding extension
     * length checks as well.
     */
    ret = mbedtls_x509_crt_parse_der(&crt, Data, Size);
#if !defined(MBEDTLS_X509_REMOVE_INFO)
    if (ret == 0) {
        ret = mbedtls_x509_crt_info((char *) buf, sizeof(buf) - 1, " ", &crt);
    }
#else
    ((void) ret);
#endif /* !MBEDTLS_X509_REMOVE_INFO */

exit:
    mbedtls_psa_crypto_free();
    mbedtls_x509_crt_free(&crt);
#else /* MBEDTLS_X509_CRT_PARSE_C */
    (void) Data;
    (void) Size;
#endif /* MBEDTLS_X509_CRT_PARSE_C */

    return 0;
}

int
dftdiBREAK_OFF()
    CODE:
        RETVAL = BREAK_OFF;
    OUTPUT:
        RETVAL

int
dftdiPARITY_MARK()
    CODE:
        RETVAL = 3;
    OUTPUT:
        RETVAL

int
dftdiSTOP_BIT_15()
    CODE:
        RETVAL = STOP_BIT_15;
    OUTPUT:
        RETVAL

int
dftdiBITS_8()
    CODE:
        RETVAL = BITS_8;
    OUTPUT:
        RETVAL

int
dftdiPARITY_NONE()
    CODE:
        RETVAL = NONE;
    OUTPUT:
        RETVAL

int
dftdiPARITY_SPACE()
    CODE:
        RETVAL = SPACE;
    OUTPUT:
        RETVAL

int
dftdiFLOW_XON_XOFF()
    CODE:
        RETVAL = SIO_XON_XOFF_HS;
    OUTPUT:
        RETVAL

int
dftdiFLOW_DISABLE()
    CODE:
        RETVAL = SIO_DISABLE_FLOW_CTRL;
    OUTPUT:
        RETVAL

int
dftdiBREAK_ON()
    CODE:
        RETVAL = BREAK_ON;
    OUTPUT:
        RETVAL

int
dftdiPARITY_EVEN()
    CODE:
        RETVAL = EVEN;
    OUTPUT:
        RETVAL

int
dftdiPARITY_ODD()
    CODE:
        RETVAL = ODD;
    OUTPUT:
        RETVAL

int
dftdiBITS_7()
    CODE:
        RETVAL = BITS_7;
    OUTPUT:
        RETVAL

int
dftdiFLOW_RTS_CTS()
    CODE:
        RETVAL = SIO_RTS_CTS_HS;
    OUTPUT:
        RETVAL

int
dftdiFLOW_DTR_DSR()
    CODE:
        RETVAL = SIO_DTR_DSR_HS;
    OUTPUT:
        RETVAL

int
dftdiSTOP_BIT_2()
    CODE:
        RETVAL = STOP_BIT_2;
    OUTPUT:
        RETVAL

int
dftdiSTOP_BIT_1()
    CODE:
        RETVAL = STOP_BIT_1;
    OUTPUT:
        RETVAL


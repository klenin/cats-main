#include <stdlib.h>
#include <time.h>
#include <string.h>
#include <ibase.h>

#define EXPORT

/*===============================================================
    fn_cats_date
================================================================= */

EXPORT char* fn_cats_date(PARAMDSC* s)
{
    char *date_s;
    struct tm times;

    if (!s || ((*s).dsc_flags & DSC_null) || 
        (*s).dsc_dtype != dtype_timestamp || !(*s).dsc_address) 
    return NULL;
  
    isc_decode_timestamp((ISC_TIMESTAMP ISC_FAR *)(*s).dsc_address, &times);

    date_s = (char *)malloc(32);        
    sprintf(
        date_s, 
        "%02d-%02d-%04d %02d:%02d",
        times.tm_mday,
        times.tm_mon + 1,
        times.tm_year + 1900,
        times.tm_hour,
        times.tm_min);

    return date_s;
}


/*===============================================================
    fn_cats_exact_date
================================================================= */

EXPORT char* fn_cats_exact_date(PARAMDSC* s)
{
    char *date_s;
    struct tm times;

    if (!s || ((*s).dsc_flags & DSC_null) || 
        (*s).dsc_dtype != dtype_timestamp || !(*s).dsc_address) 
    return NULL;
  
    isc_decode_timestamp((ISC_TIMESTAMP ISC_FAR *)(*s).dsc_address, &times);

    date_s = (char *)malloc(32);        
    sprintf(
        date_s, 
        "%02d-%02d-%04d %02d:%02d:%02d",
        times.tm_mday,
        times.tm_mon + 1,
        times.tm_year + 1900,
        times.tm_hour,
        times.tm_min,
        times.tm_sec);

    return date_s;
}


/*===============================================================
    fn_cats_to_date
================================================================= */

EXPORT ISC_TIMESTAMP* fn_cats_to_date(char* date_s)
{
    struct tm times;
    char *date_zs;
    ISC_TIMESTAMP* date;
    int length;

    length = *(short *)date_s;
    date_zs = (char *)malloc(length + 1);

    memcpy(date_zs, date_s + 2, length);
    date_zs[length] = '\0';

    memset(&times, 0, sizeof(times));    
    if (sscanf(
        date_zs, 
        "%02d-%02d-%04d %02d:%02d",
        &times.tm_mday,
        &times.tm_mon,
        &times.tm_year,
        &times.tm_hour,
        &times.tm_min) != 5)
    {   
        free(date_zs);
        return NULL;
    }   
    free(date_zs);

    times.tm_year -= 1900;
    times.tm_mon -= 1;
    times.tm_isdst = -1;
    
    mktime(&times);
 
    date = (ISC_TIMESTAMP *)malloc(sizeof(ISC_TIMESTAMP));
    isc_encode_timestamp(&times, date);

    return date;
}



/*===============================================================
    fn_cats_to_exact_date
================================================================= */

EXPORT ISC_TIMESTAMP* fn_cats_to_exact_date(char* date_s)
{
    struct tm times;
    char *date_zs;
    ISC_TIMESTAMP* date;
    int length;

    length = *(short *)date_s;
    date_zs = (char *)malloc(length + 1);

    memcpy(date_zs, date_s + 2, length);
    date_zs[length] = '\0';

    memset(&times, 0, sizeof(times));    
    if (sscanf(
        date_zs, 
        "%02d-%02d-%04d %02d:%02d:%02d",
        &times.tm_mday,
        &times.tm_mon,
        &times.tm_year,
        &times.tm_hour,
        &times.tm_min,
        &times.tm_sec) != 6)
    {   
        free(date_zs);
        return NULL;
    }   
    free(date_zs);

    times.tm_year -= 1900;
    times.tm_mon -= 1;
    times.tm_isdst = -1;
    
    mktime(&times);
 
    date = (ISC_TIMESTAMP *)malloc(sizeof(ISC_TIMESTAMP));
    isc_encode_timestamp(&times, date);

    return date;
}


/*===============================================================
    fn_cats_sysdate
================================================================= */

EXPORT ISC_TIMESTAMP* fn_cats_sysdate()
{
    time_t t;
    ISC_TIMESTAMP* date;

    time (&t);
    
    date = (ISC_TIMESTAMP *)malloc(sizeof(ISC_TIMESTAMP));
    isc_encode_timestamp(localtime(&t), date);

    return date;
}


/*===============================================================
    fn_cats_difftime
================================================================= */

EXPORT double fn_cats_difftime(void* s1, void* s2)
{
    struct tm times1, times2;
    time_t t1, t2;
    
    isc_decode_timestamp((ISC_TIMESTAMP ISC_FAR *)s1, &times1);
    isc_decode_timestamp((ISC_TIMESTAMP ISC_FAR *)s2, &times2);    
    
    t1 = mktime(&times1);
    t2 = mktime(&times2);    

    return difftime(t2, t1);
}

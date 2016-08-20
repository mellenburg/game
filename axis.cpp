// NOTE: Does not support inverse axis yet
#include "axis.h"
Axis::Axis (short int x0, short int x, double v0, double v) {
    start_loc = x0;
    end_loc = x;
    start_val = v0;
    end_val = v;
    len = x - x0;
    range = v - v0;
    center = (len/2) + x0;
}

short int Axis::transform(double x){
    return (short int)(((x-start_val)/range) * double(len))+start_loc;
}

short int Axis::scale(double x){
    return (short int)(x/range*double(len));
}

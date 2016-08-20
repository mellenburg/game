class Axis {
        short int len;
        double range;
    public:
        short int start_loc;
        short int end_loc;
        short int center;
        double start_val;
        double end_val;
        Axis (short, short, double, double);
        short int transform  (double);
        short int scale  (double);
};

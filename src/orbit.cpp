// GLM Mathemtics
#define GLM_FORCE_RADIANS
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>

#include <cmath>
#include <iostream>
#include "orbit.h"

#define PI 3.14159265

vec3D cross_product (vec3D &u, vec3D &v){
    vec3D w;
    w.i = u.j*v.k - u.k*v.j;
    w.j = u.k*v.i - u.i*v.k;
    w.k = u.i*v.j - u.j*v.i;
    return w;
}

vec3D vec_copy (vec3D &u){
    vec3D v;
    v.i = u.i;
    v.j = u.j;
    v.k = u.k;
    return v;
}

void vec_copy_to (vec3D &u, vec3D& v){
    v.i = u.i;
    v.j = u.j;
    v.k = u.k;
}

vec4D vec_copy (vec4D &u){
    vec4D v;
    v.i = u.i;
    v.j = u.j;
    v.k = u.k;
    v.t = u.t;
    return v;
}

double dot_product (vec3D &u, vec3D &v)
{
    return (u.i*v.i)+(u.j*v.j)+(u.k*v.k);
}

double norm (vec3D &u)
{
    return std::sqrt(dot_product(u, u));
}

vec3D vec_scale (double f, vec3D &u)
{
    return vec3D {f*u.i, f*u.j, f*u.k};
}

vec3D vec_add(vec3D &u, vec3D &v){
    vec3D w;
    w.i = u.i + v.i;
    w.j = u.j + v.j;
    w.k = u.k + v.k;
    return w;
}

double c2(double psi)
{
    long double res;
    if (psi > 1.0)
    {
        res = (1.0 - std::cos(std::sqrt(psi))) / psi;
    }
    else if (psi < -1.0)
    {
        res = (std::cosh(std::sqrt(-1*psi))-1.0) / (-1.0 * psi);
    }
    else
    {
        res = .5;
        long double delta = (-1.0*psi) / std::tgamma(5);
        int k = 1;
        while (res+delta != res)
        {
            res = res + delta;
            k++;
            delta = pow((-1.0*psi), k)/std::tgamma(2*k + 3);
        }
    }
    return (double) res;
}

double c3(double psi)
{
    long double res;
    if (psi > 1.0)
    {
        res =  (sqrt(psi) - sin(sqrt(psi))) / pow(psi, 1.5);
    }
    else if (psi < -1.0)
    {
        res = (std::sinh(sqrt(-1.0*psi)) - sqrt(-1.0*psi)) / (-1.0 * psi * std::sqrt(-1.0*psi));
    }
    else
    {
        res = 1.0 / 6.0;
        long double delta = (-1.0 * psi) / std::tgamma(6);
        int k = 1;
        while (res+delta != res)
        {
            res = res + delta;
            k++;
            delta = std::pow((-1.0*psi), k) / std::tgamma(2*k+4);
        }
    }
    return (double) res;
}

EarthOrbit::EarthOrbit (vec3D& r_in, vec3D& v_in){
    vec_copy_to(r_in, r);
    vec_copy_to(v_in, v);
    rv2coe();
}

EarthOrbit::~EarthOrbit (){}

void EarthOrbit::rv2coe()
{
    vec3D z = {0., 0., 1.0};
    vec3D h = cross_product(r, v);
    double norm_h = norm(h);
    vec3D z_cross_h =  cross_product(z, h);
    vec3D n = vec_scale(1.0/norm_h, z_cross_h);
    vec3D e_r = vec_scale((dot_product(v, v)-(k/norm(r)))/k, r);
    vec3D e_v = vec_scale((-1.0*dot_product(r, v))/k, v);
    vec3D e = vec_add(e_r, e_v);
    ecc = norm(e);
    p = dot_product(h, h) / k;
    a = p / (1.0 - pow(ecc, 2.0));
    b = a * std::sqrt(1.0 - pow(ecc, 2));
    inc = std::acos(h.k/norm(h));
    vec3D h_cross_n = cross_product(h, n);
    vec3D h_cross_n_s = vec_scale(1.0/norm_h, h_cross_n);
    float tol = 1.0e-8;
    bool equatorial = std::abs(inc) < tol;
    bool circular = ecc < tol;
    if (equatorial && !circular)
    {
        raan = 0;
        argp = std::atan2(e.j, e.i);
        vec3D e_cross_r = cross_product(e, r);
        vec3D between = vec_scale((1.0/norm_h), e_cross_r);
        nu = std::atan2(dot_product(h, between), dot_product(r, e));
    } else if (!equatorial && circular) {
        raan = std::atan2(n.j, n.i);
        argp = 0.0f;
        nu = std::atan2(dot_product(r, h_cross_n_s), dot_product(r, n));
    } else if (equatorial && circular) {
        raan = 0.0;
        argp = 0.0;
        nu = std::atan2(r.j, r.i);
    } else {
        raan = std::atan2(n.j, n.i);
        vec3D h_cross_e = cross_product(h, e);
        vec3D h_cross_e_s = vec_scale(1.0/norm_h, h_cross_e);
        argp = std::atan2(dot_product(e, h_cross_n_s), dot_product(e, n));
        nu = std::atan2(dot_product(r, h_cross_e_s), dot_product(r, e));
    }
    r_a = a * (1.0 + ecc);
    r_p = a * (1.0 - ecc);
    period = 2*PI*sqrt(pow(a, 3)/k);
    norm_r = norm(r);
    norm_v = norm(v);
}

void EarthOrbit::propagate(double tof)
{
    //Compute Lagrange coefficients
    vec3D r0 = vec_copy(r);
    vec3D v0 = vec_copy(v);
    double dot_r0v0 = dot_product(r0, v0);
    double norm_r0 = norm(r0);
    double sqrt_mu = std::pow(k, .5);
    double alpha = (2/norm_r0)-(dot_product(v0, v0)/k);
    double xi_new;
    if (alpha > 0)
    {
        //Elliptical Orbit
        xi_new = sqrt_mu * tof * alpha;
    }
    else if (alpha < 0)
    {
        //Hyperbolic Orbit
        xi_new = std::sqrt(-1.0/alpha)*log((-2.0*k*alpha*tof)/(dot_r0v0+(sqrt(-1.0*k/alpha)*(1.0-norm_r0*alpha))));
    }
    else
    {
        //Parabolic Orbit
        xi_new = sqrt_mu * tof / norm_r0;
    }
    //Newton-Raphson iteration on the Kepler equation
    int count = 0;
    double xi;
    double psi;
    double c2_psi;
    double c3_psi;
    double norm_r;
    while (count < numiter)
    {
        xi = xi_new;
        psi = xi * xi * alpha;
        c2_psi = c2(psi);
        c3_psi = c3(psi);
        norm_r = (xi*xi*c2_psi +
                dot_r0v0/sqrt_mu*xi * (1.0-psi*c3_psi) +
                norm_r0 * (1.0 - psi * c2_psi));
        xi_new = xi + (sqrt_mu * tof - xi*xi*xi*c3_psi -
                dot_r0v0 / sqrt_mu * xi * xi * c2_psi -
                norm_r0 * xi * (1 - psi * c3_psi)) / norm_r;
        if (std::abs((xi_new - xi)/xi_new) < rtol || std::abs( xi_new - xi) < rtol)
        {
            break;
        }
        else
        {
            count ++;
        }
        // TODO: raise error when too many iterations reached
    }
    double f = 1.0 - std::pow(xi, 2) / norm_r0 * c2_psi;
    double g = tof - std::pow(xi, 3) / sqrt_mu * c3_psi;
    double gdot = 1.0 - std::pow(xi, 2) / norm_r * c2_psi;
    double fdot = sqrt_mu / (norm_r * norm_r0) * xi * (psi * c3_psi - 1.0);
    vec3D f_r0 = vec_scale(f, r0);
    vec3D g_v0 = vec_scale(g, v0);
    r = vec_add(f_r0, g_v0);
    vec3D fdot_r0 = vec_scale(fdot, r0);
    vec3D gdot_v0 = vec_scale(gdot, v0);
    v = vec_add(fdot_r0, gdot_v0);
    rv2coe();
}

void EarthOrbit::maneuver(vec4D &dv){
    propagate(dv.t);
    vec3D v0 = v;
    vec3D dv_space = {dv.i, dv.j, dv.k};
    v = vec_add(v0, dv_space);
    rv2coe();
}

void EarthOrbit::clone(EarthOrbit& e) {
    vec_copy_to(e.r, r);
    vec_copy_to(e.v, v);
    r_p = e.r_p;
    r_a = e.r_a;
    ecc = e.ecc;
    p = e.p;
    a = e.a;
    b = e.b;
    inc = e.inc;
    raan = e.raan;
    argp = e.argp;
    nu = e.nu;
    norm_r = e.norm_r;
    norm_v = e.norm_v;
}

void EarthOrbit::relative_maneuver(vec4D &dv){
    vec3D i = vec_scale(1.0/norm(v), v);
    vec3D r_cross_v = cross_product(r, v);
    vec3D k = vec_scale(1.0/norm(r_cross_v), r_cross_v);
    vec3D i_cross_k = cross_product(i, k);
    vec3D j = vec_scale(-1.0/norm(i_cross_k), i_cross_k);
    i = vec_scale(dv.i, i);
    j = vec_scale(dv.j, j);
    k = vec_scale(dv.k, k);
    vec3D manjk = vec_add(j, k);
    vec3D manijk = vec_add(i , manjk);
    vec4D man_t = {manijk.i, manijk.j, manijk.k, dv.t};
    maneuver(man_t);
}

void EarthOrbit::relative_maneuver(glm::vec3 dv, double t){
    vec3D i = vec_scale(1.0/norm(v), v);
    vec3D r_cross_v = cross_product(r, v);
    vec3D k = vec_scale(1.0/norm(r_cross_v), r_cross_v);
    vec3D i_cross_k = cross_product(i, k);
    vec3D j = vec_scale(-1.0/norm(i_cross_k), i_cross_k);
    i = vec_scale(dv.x, i);
    j = vec_scale(dv.y, j);
    k = vec_scale(dv.z, k);
    vec3D manjk = vec_add(j, k);
    vec3D manijk = vec_add(i , manjk);
    vec4D man_t = {manijk.i, manijk.j, manijk.k, t};
    maneuver(man_t);
}

// GLM Mathemtics
#define GLM_FORCE_RADIANS
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>

#include <cmath>
#include <iostream>
#include "orbit.h"

#define PI 3.14159265

GLfloat c2(GLfloat psi)
{
    GLfloat res;
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
        GLfloat delta = (-1.0*psi) / std::tgamma(5);
        int k = 1;
        while (res+delta != res)
        {
            res = res + delta;
            k++;
            delta = pow((-1.0*psi), k)/std::tgamma(2*k + 3);
        }
    }
    return (GLfloat) res;
}

GLfloat c3(GLfloat psi)
{
    GLfloat res;
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
        GLfloat delta = (-1.0 * psi) / std::tgamma(6);
        int k = 1;
        while (res+delta != res)
        {
            res = res + delta;
            k++;
            delta = std::pow((-1.0*psi), k) / std::tgamma(2*k+4);
        }
    }
    return (GLfloat) res;
}

EarthOrbit::EarthOrbit (glm::vec3& r_in, glm::vec3& v_in)
{
    r = r_in;
    v = v_in;
}

EarthOrbit::~EarthOrbit (){}

void EarthOrbit::rv2coe()
{
    glm::vec3 z {0.0f, 0.0f, 1.0f};
    glm::vec3 h = glm::cross(r, v);
    GLfloat h_length = glm::length(h);
    GLfloat r_length = glm::length(r);
    glm::vec3 n = glm::cross(z, h)/h_length;
    glm::vec3 e = (((glm::dot(v, v) - (k/r_length)) * r) - (glm::dot(r, v) * v))/k;
    ecc = glm::length(e);
    p = glm::dot(h, h) / k;
    a = p / (1.0 - pow(ecc, 2.0));
    b = a * std::sqrt(1.0 - pow(ecc, 2));
    inc = std::acos(h.z/h_length);
    glm::vec3 h_cross_n_s = glm::cross(h, n)/h_length;
    GLfloat tol = 1.0e-8;
    bool equatorial = std::abs(inc) < tol;
    bool circular = ecc < tol;
    if (equatorial && !circular)
    {
        raan = 0;
        argp = std::atan2(e.y, e.x);
        nu = std::atan2(glm::dot(h, glm::cross(e, r)/h_length), glm::dot(r, e));
    } else if (!equatorial && circular) {
        raan = std::atan2(n.y, n.x);
        argp = 0.0f;
        nu = std::atan2(glm::dot(r, h_cross_n_s), glm::dot(r, n));
    } else if (equatorial && circular) {
        raan = 0.0;
        argp = 0.0;
        nu = std::atan2(r.y, r.x);
    } else {
        raan = std::atan2(n.y, n.x);
        argp = std::atan2(glm::dot(e, h_cross_n_s), glm::dot(e, n));
        nu = std::atan2(glm::dot(r, glm::cross(h, e)/h_length), glm::dot(r, e));
    }
    r_a = a * (1.0 + ecc);
    r_p = a * (1.0 - ecc);
    period = 2*PI*sqrt(pow(a, 3)/k);
}

void EarthOrbit::propagate(GLfloat tof)
{
    //Compute Lagrange coefficients
    glm::vec3 r0 = r;
    glm::vec3 v0 = v;
    GLfloat dot_r0v0 = glm::dot(r0, v0);
    GLfloat norm_r0 = glm::length(r0);
    GLfloat sqrt_mu = std::pow(k, .5);
    GLfloat alpha = (2/norm_r0)-(glm::dot(v0, v0)/k);
    GLfloat xi_new;
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
    GLfloat xi;
    GLfloat psi;
    GLfloat c2_psi;
    GLfloat c3_psi;
    GLfloat norm_r;
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
    GLfloat f = 1.0 - std::pow(xi, 2) / norm_r0 * c2_psi;
    GLfloat g = tof - std::pow(xi, 3) / sqrt_mu * c3_psi;
    GLfloat gdot = 1.0 - std::pow(xi, 2) / norm_r * c2_psi;
    GLfloat fdot = sqrt_mu / (norm_r * norm_r0) * xi * (psi * c3_psi - 1.0);
    r = f * r0 + g * v0;
    v = fdot * r0 + gdot * v0;
}

void EarthOrbit::maneuver(glm::vec4 &dv)
{
    propagate(dv.w);
    v = v + glm::vec3(dv);
}

void EarthOrbit::clone(EarthOrbit& e)
{
    r = e.r;
    v = e.v;
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
}

void EarthOrbit::relative_maneuver(glm::vec3 dv, GLfloat t)
{
    glm::vec3 i = glm::normalize(v);
    glm::vec3 k = glm::normalize(glm::cross(r, v));
    glm::vec3 j = -1.0f * glm::normalize(glm::cross(i, k));
    glm::vec4 man_t = glm::vec4(dv.x*i + dv.y*j + dv.z*k, t);
    // FIXME: refactor time scaling in here:
    maneuver(man_t);
}

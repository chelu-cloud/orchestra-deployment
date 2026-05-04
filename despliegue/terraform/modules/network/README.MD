# NOTES

## SUBNET ASSOCIATIONS

       __________________________________________
      |           INTERNET GATEWAY (IGW)         |  <-- Puerta de entrada/salida
      |__________________________________________|
                           |
      _____________________V_____________________
     |                VPC A (10.0.0.0/16)        |
     |___________________________________________|
              |                             |
      ________V________             ________V________
     |      AZ 1       |           |      AZ 2       |
     |_________________|           |_________________|
     |                 |           |                 |
     | [ Sub. Pública ]|           | [ Sub. Pública ]| <-- Ingress / NAT GW
     |   (10.0.1.0/24) |           |   (10.0.2.0/24) |
     |                 |           |                 |
     | [ Sub. Priv App]|           | [ Sub. Priv App]| <-- Backend Java / Vue
     |  (10.0.3.0/24)  |           |  (10.0.4.0/24)  |
     |                 |           |                 |
     | [ Sub. Priv Dat]|           | [ Sub. Priv Dat]| <-- RDS Postgres
     |  (10.0.5.0/24)  |           |  (10.0.6.0/24)  |
     |_________________|           |_________________|

## ASSOCIATIONS (Routes of the route tables)

### **Route Table: PÚBLICA**

*Asociada a: Subnet Pública 1 (AZ1) y Subnet Pública 2 (AZ2)*

* **Local Route:** `10.0.0.0/16` -> `local` (exist by default)
* **Default Route:** `0.0.0.0/0` -> `Internet Gateway (IGW)` 

### **Route Table: PRIVADA APP**

* **Local Route:** `10.0.0.0/16` -> `local` (exist by default)
* **Default Route:** `0.0.0.0/0` -> **`NAT Gateway`**

### **Route Table: PRIVATE DATA** (Exist by default)

* **Local Route:** `10.0.0.0/16` -> `local`


---

**NOTE:** NAT Gateway is anything more than a translator. It is allocated at PUBLIC SUBNETS almost always.




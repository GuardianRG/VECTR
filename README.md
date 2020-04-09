# ![VECTR](media/vectr-logo-small.png)

VECTR documentation can be found here:
[https://docs.vectr.io](https://docs.vectr.io)

VECTR is a tool that facilitates tracking of your red and blue team testing activities to measure detection and prevention capabilities across different attack scenarios.  VECTR provides the ability to create assessment groups, which consist of a collection of Campaigns and supporting Test Cases to simulate adversary threats.  Campaigns can be broad and span activity across the kill chain, from initial compromise to privilege escalation and lateral movement and so on, or can be a narrow in scope to focus on specific detection layers, tools, and infrastructure.  VECTR is designed to promote full transparency between offense and defense, encourage training between team members, and improve detection & prevention success rate across the environment.   

VECTR is focused on common indicators of attack and behaviors that may be carried out by any number of threat actor groups, with varying objectives and levels of sophistication.  VECTR can also be used to replicate the step-by-step TTPs associated with specific groups and malware campaigns, however its primary purpose is to replicate attacker behaviors that span multiple threat actor groups and malware campaigns, past, present and future.  VECTR is meant to be used over time with targeted campaigns, iteration, and measurable enhancements to both red team skills and blue team detection capabilities.  Ultimately the goal of VECTR is to make a network resilient to all but the most sophisticated adversaries and insider attacks.

# ![VECTR](media/VectrMitreHeatmap.png)

# ![VECTR](media/VectrCampaignView.png)

# ![VECTR](media/ImportData.png)

# ![VECTR](media/historicalTrending.png)

## Environment Notes

## Installation Scripts (Preferred)
See the [wiki](https://github.com/SecurityRiskAdvisors/VECTR/wiki/Installation) for complete documentation

![WARNING](https://placehold.it/15/f03c15/000000?text=+) **WARNING FOR USERS UPGRADING FROM V5.0.\* OR EARLIER**

Please read instructions carefully for [Upgrading a VECTR instance](https://github.com/SecurityRiskAdvisors/VECTR/wiki/Upgrading-an-existing-VECTR-installation)

You must perform additional manual steps or you will encounter login errors.  

## Linux Docker Installation (Manual)

1. Install [Docker Engine](https://docs.docker.com/engine/installation/) and [Docker Compose](https://docs.docker.com/compose/install/).

2. Download the [release package](https://github.com/SecurityRiskAdvisors/VECTR/releases/latest).

3. Extract the release package to */opt/vectr* or copy all extracted files to this folder.  **WARNING: You will get errors if vectr.properties is not under */opt/vectr/config* and all *\*.war* files are not under */opt/vectr/wars***
	
4. Run `docker compose` from the top directory where docker-compose.yml is located. Proxy configurations might need to be added to the YAML file in order for the containers to have internet access if your environment requires proxies. In addition to the docker-compose.yml, an environment-specific configuration file, devSsl.yml (https) is included. You may define the port and volume usages for individual environments using a configuration like this.  
	for HTTPS, put your .crt and .key under /opt/vectr/config.  If you want a self-signed, you can use openssl to generate one:
	```sh
	$ openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 -subj "/C=SomeCountry/ST=SomeState/L=SomeLocality/O=SomeOrg/CN=SomeCommonName" -keyout /opt/vectr/config/ssl.key -out /opt/vectr/config/ssl.crt
	```
	
	once your .crt and .key are generated, you can run the devSsl.yml environment file:
	```sh
	$ sudo docker-compose -f docker-compose.yml -f devSsl.yml -p dev up -d
	Creating vectr_mongo
	Creating vectr_tomcat
	```
	
	
5. Check the status of the containers with `docker ps`.

	```sh
	$ sudo docker ps
	CONTAINER ID        IMAGE                         COMMAND                  CREATED             STATUS              PORTS                                            NAMES
	d7a87f88bb71        vectr_tomcat:latest           "catalina.sh run"        4 seconds ago       Up 2 seconds        0.0.0.0:8080->8080/tcp                           vectr_tomcat
	dcf593d84e1e        mongo:3.4                   "/entrypoint.sh mongo"   5 seconds ago       Up 4 seconds        0.0.0.0:27017->27017/tcp                         vectr_mongo
	```
### Docker Windows

So far we are not able to get Docker on Windows to work properly.  The mongo container will not persist data to docker-compose volumes.  This may be related to how mongo saves data in addition to how file permissions work for the Windows base Docker VM.  We've seen discussion about named volumes working, but we haven't investigated this yet.

	
## Usage

The VECTR webapp is available at https://your_docker_host:8081, if you used the devSsl.yml. Log in with the default admin credentials: user admin and password 11_ThisIsTheFirstPassword_11.  Please change your password after initial login in the user profile menu.

Check out our [How-to Videos](https://github.com/SecurityRiskAdvisors/VECTR/wiki/How-To-Videos) for getting started in VECTR once you have it installed 

## General

* Presentation layer built on AngularJS with some Angular Material UI components
* Support for OAuth 2.0
* REST API powered by Apache CXF and JAX-RS
* Support for TLS endpoints (for VECTR Community Edition you will need to obtain your own trusted certificate, the tool does not ship with an untrusted self-signed cert)

## Documentation

### Feature Breakdowns By Release

[VECTR v5.4.0 Feature Breakdown](https://github.com/SecurityRiskAdvisors/VECTR/blob/master/media/VECTR%20v5_4%20Feature%20Breakdown.pdf)

## Team
LEAD PROGRAMMERS:
* Carl Vonderheid
* Galen Fisher

PROGRAMMERS:
* Daniel Hong
* Andrew Scott
* Patrick Hislop
* Nick Galante

DESIGN & REQUIREMENTS:
* Phil Wainwright

GRAPHIC DESIGN & MARKETING:
* Doug Webster

[![Security Risk Advisors](media/SRA-logo-primary-small.png)](https://securityriskadvisors.com)

## License

Please see the [EULA](./VECTR%20End%20User%20License%20Agreement.pdf)

Atomic Red [LICENSE](https://github.com/redcanaryco/atomic-red-team/blob/master/LICENSE.txt)


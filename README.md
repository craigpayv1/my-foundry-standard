# OVERVIEW

This solution will deploy Microsoft Foundry into a single existing Resource Group. 

![alt text](images/image01.png)

The code in this solution is effectively a merger of two repos, one by this author, another is Microsoft's official sample code for Foundry:

* Azure AI services using the old AI Hub approach: https://github.com/craigpayv1/azure-ai
* Microsoft official Foundry sample code, albeit using old AzApi API versions (which causes bugs in the Foundry portal), no NSGs, no jump-box and more: https://github.com/microsoft-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-terraform/15a-private-network-standard-agent-setup

## Tags
This deployment will ignore Tags auto-applied by Azure Policy.

# PRE-REQS

An Azure Resource Group.

Visual Studio Code, Terraform and Azure CLI.

Clone this repo, open in Visual Studio Code.

Owner RBAC permissions on the Resource Group (to apply roles in-code).

> **Important:** You MUST have OWNER permissions on the Resource Group BEFORE you run a Terraform Apply or it will fail.

# LOGIN TO AZURE

Use the following commands to authenticate before you run Terraform:

```
az logout
az account clear

az login --tenant [YOUR_TENANT_ID] --output none
az account set --subscription [YOUR_SUBSCRIPTION_ID]
```

Replace [YOUR_TENANT_ID] & [YOUR_SUBSCRIPTION_ID] in the above with appropriate values.

# TERRAFORM INIT, PLAN, APPLY & DESTROY

Use the following Terraform commands as usual:

```
terraform init

terraform plan

terraform apply

terraform destroy
```

Your Terraform deployment should succeed without error:

![alt text](images/image02.png)


# SECURITY

This Foundry solution is secured with private IP networking as well as Entra. Public access is deactivated by default. The public IP address of the installer is automatically added to Network rules to allow access to the solution. For example:

![alt text](images/image03.png)

The public IP address of the installer is automatically added to a Network Security Rule (NSG) allowing RDP access to a Virtual Machine (VM) deployed with the solution. This VM isn't specifically needed for access to the solution, but it's included to test private networking:

![alt text](images/image04.png)

The Entra identity of the installer is automatically added with various roles to resources in the solution:

![alt text](images/image05.png)

API keys are disabled:

![alt text](images/image06.png)

# ACCESS

Public access to the solution is only available from the public IP where the Terraform deployment was run (using Network rules on the Foundry & Search resources, which could be updated). Alternatively, the solution deploys a Virtual Machine which can be used as a jump-box, though this is similarly only available from the public IP where the Terraform was run (using an RDP NSG rule, which again could be updated). 

In a real world deployment, access via VNet peering to a VNet hub where a Site-to-Site VPN or ExpressRoute connectivity is enabled would be more likely.

# DEMO & TESTING

## Upload Demo Data File

1. Locate the Storage Account & navigate into the Containers blade:

![alt text](images/image07.png)

2. Navigate into the **ragdata** container & upload the Northwind Healthcare PDF from the **demo_data** folder in this repo:

![alt text](images/image08.png)

3. Locate and navigate into the Foundry resource in the Azure portal:

![alt text](images/image09.png)

![alt text](images/image10.png)

4. Click the button **Go to Foundry portal**:

![alt text](images/image11.png)

5. Navigate to **Build**:

![alt text](images/image12.png)

6. Click **New agent** to build a new agent:

![alt text](images/image13.png)

7. Create and open in playground:

![alt text](images/image14.png)

8. Remove Web Search (under Tools). Add a new Tool and select Search. Select the Search resource deployed with Terraform:

![alt text](images/image15.png)

9. Click **Create a new index**. Select the Storage Account, Container, authentication and ADA model deployed with Terraform:

![alt text](images/image16.png)

10. Click **Create index** and **wait** until the following screen appears (you can click **Add**):

![alt text](images/image17.png)

11. The index is now being created in the background. Check progress by navigating to the Search resource in the Azure portal. Then navigate to the Indexers blade:

![alt text](images/image18.png)

12. Navigate to the Indexes blade to view the index itself. **Document count** will read as zero until indexing is 100% complete:

![alt text](images/image19.png)

13. Once the **initial** stage of indexing is complete, the indexer will show as complete:

![alt text](images/image20.png)

14. Navigate to the Indexes blade again and **wait** until document count reports a non-zero value, indicating that indexing is 100% complete:

![alt text](images/image21.png)
 
15. Navigate back to the Foundry portal. Test the playground chatbot with a test prompt such as 'hi':

![alt text](images/image22.png)

16. Further test with playground chatbot with a prompt such as:

``
are prescription drug costs taken into consideration with the Contoso Electronics health plan?
``

![alt text](images/image23.png)

17. Check that document references are embedded:

![alt text](images/image24.png)

That's it! Your Foundry deployment is now complete.

# Virtual Machine Access

A Virtual Machine is included with this solution. This VM isn't specifically needed but it's a good approximation of private access to the Foundry solution. 

A real world Foundry deployment wouldn't allow any public access. Such access would only be allowed via the private networking configured in this solution. The VNet deployed with this solution would likely be peered to a hub VNet with a site-to-site VPN or ExpressRoute or Bastion allowing secure access.

Access to the VM in the solution is via RDP. The password to access this VM is automatically generated by code and stored in the solution's Key Vault:

![alt text](images/image25.png)

After RDP'ing to the jump box, the above **Demo & Testing** steps should all work identically without any errors:

![alt text](images/image26.png)

# Troubleshooting

If you experience errors during the Terraform deploy, double check you have the Owner role to the Resource Group where you are deploying the solution. Owner is required to assign roles.

If, in the future, you experience errors using Foundry in the Virtual Machine, but you don't experience the same errors accessing Foundry via your workstation (access via your public IP), check the latest API versions for resources deployed by Terraform using the AzApi provider. This was one of the main failings of the Microsoft sample code which used API versions over a year old which caused these strange 'private networking only' related errors. As of the time of writing this README (01 September 2026), the various API versions in this repo work perfectly, but I can't guarantee this will be the case for future versions. It might take some work to figure out the correct API versions.
